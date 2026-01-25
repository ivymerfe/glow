package renderer

import "base:runtime"
import "core:dynlib"
import "core:log"
import vk "vendor:vulkan"


VulkanContext :: struct {
	instance:           vk.Instance,
	physical_device:    vk.PhysicalDevice,
	device_props:       vk.PhysicalDeviceProperties,
	mem_props:          vk.PhysicalDeviceMemoryProperties,
	device:             vk.Device,
	graphics_queue_idx: u32,
	graphics_queue:     vk.Queue,
	present_queue_idx:  u32,
	present_queue:      vk.Queue,
}

vk_try :: proc(result: vk.Result, location := #caller_location) {
	if result != .SUCCESS {
		log.panicf("Vulkan failed with result = %v", result, location)
	}
}

create_vulkan_context :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) -> VulkanContext {
	vkc: VulkanContext
	vkc.instance = instance
	pick_device(&vkc)
	create_logical_device(&vkc, surface)
	return vkc
}

destroy_vulkan_context :: proc(vkc: ^VulkanContext) {
	if vkc.device != nil {
		vk.DestroyDevice(vkc.device, nil)
	}
}

create_vk_instance :: proc() -> vk.Instance {
	g_module, loaded := dynlib.load_library("libvulkan.so.1", true)
	if !loaded {
		g_module, loaded = dynlib.load_library("libvulkan.so", true)
	}
	ensure(loaded, "Failed to load Vulkan library!")
	ensure(g_module != nil, "Failed to load Vulkan library module!")

	vk_get_instance_proc_addr, found := dynlib.symbol_address(g_module, "vkGetInstanceProcAddr")
	ensure(found, "Failed to get instance process address!")

	vk.load_proc_addresses_global(vk_get_instance_proc_addr)
	ensure(vk.CreateInstance != nil, "Failed to load vulkan function pointers")

	create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = "Glow",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "Glow",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.MAKE_VERSION(1, 4, 330),
		},
	}
	extensions :=
		[]cstring {
			vk.KHR_SURFACE_EXTENSION_NAME,
			vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME,
			vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
		} when ENABLE_VALIDATION else []cstring {
			vk.KHR_SURFACE_EXTENSION_NAME,
			vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME,
		}

	when ENABLE_VALIDATION {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1

		severity: vk.DebugUtilsMessageSeverityFlagsEXT
		if context.logger.lowest_level <= .Error {
			severity |= {.ERROR}
		}
		if context.logger.lowest_level <= .Warning {
			severity |= {.WARNING}
		}
		if context.logger.lowest_level <= .Info {
			severity |= {.INFO}
		}
		if context.logger.lowest_level <= .Debug {
			severity |= {.VERBOSE}
		}

		dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE}, // all of them.
			pfnUserCallback = vk_messenger_callback,
		}
		create_info.pNext = &dbg_create_info
	}
	create_info.enabledExtensionCount = u32(len(extensions))
	create_info.ppEnabledExtensionNames = raw_data(extensions)

	instance := vk.Instance{}
	vk_try(vk.CreateInstance(&create_info, nil, &instance))
	vk.load_proc_addresses_instance(instance)
	return instance
}

@(private = "file")
vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	msg := pCallbackData.pMessage
	when ENABLE_VALIDATION {
		if .ERROR in messageSeverity {
			log.errorf("Vulkan Validation: %s", msg)
		} else if .WARNING in messageSeverity {
			log.warnf("Vulkan Validation: %s", msg)
		} else if .INFO in messageSeverity {
			log.infof("Vulkan Validation: %s", msg)
		} else {
			log.debugf("Vulkan Validation: %s", msg)
		}
	}
	return false
}

@(private = "file")
pick_device :: proc(vkc: ^VulkanContext) {
	device_count: u32
	vk_try(vk.EnumeratePhysicalDevices(vkc.instance, &device_count, nil))
	if device_count == 0 {
		log.panic("No GPU found!")
	}

	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk_try(vk.EnumeratePhysicalDevices(vkc.instance, &device_count, raw_data(devices)))

	vkc.physical_device = devices[0]
	vk.GetPhysicalDeviceProperties(vkc.physical_device, &vkc.device_props)
	vk.GetPhysicalDeviceMemoryProperties(vkc.physical_device, &vkc.mem_props)

	log.infof("Selected device: %s", bytes_to_string(&vkc.device_props.deviceName))
}

create_logical_device :: proc(vkc: ^VulkanContext, surface: vk.SurfaceKHR) {
	if !find_queue_family_indexes(vkc, surface) {
		log.panic("Cannot find device queues: graphics & present")
	}
	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &vk.PhysicalDeviceFeatures2 {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			features = {shaderInt64 = true},
			pNext = &vk.PhysicalDeviceVulkan13Features {
				sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
				pNext = &vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
					sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
					extendedDynamicState = true,
				},
				synchronization2 = true,
				dynamicRendering = true,
			},
		},
		pQueueCreateInfos       = &vk.DeviceQueueCreateInfo {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = vkc.graphics_queue_idx,
			queueCount = 1,
			pQueuePriorities = raw_data([]f32{1}),
		},
		queueCreateInfoCount    = 1,
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
	}
	vk_try(vk.CreateDevice(vkc.physical_device, &device_create_info, nil, &vkc.device))
	vk.GetDeviceQueue(vkc.device, vkc.graphics_queue_idx, 0, &vkc.graphics_queue)
	vk.GetDeviceQueue(vkc.device, vkc.present_queue_idx, 0, &vkc.present_queue)
}

@(private = "file")
find_queue_family_indexes :: proc(vkc: ^VulkanContext, surface: vk.SurfaceKHR) -> bool {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(vkc.physical_device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(vkc.physical_device, &count, raw_data(families))

	graphics_idx := -1
	present_idx := -1
	for family, i in families {
		support_graphics_and_compute :=
			.GRAPHICS in family.queueFlags && .COMPUTE in family.queueFlags
		support_present: b32
		vk_try(
			vk.GetPhysicalDeviceSurfaceSupportKHR(
				vkc.physical_device,
				u32(i),
				surface,
				&support_present,
			),
		)
		if support_graphics_and_compute {
			graphics_idx = i
		}
		if support_present {
			present_idx = i
		}
		if support_graphics_and_compute && support_present {
			break
		}
	}
	if graphics_idx != -1 && present_idx != -1 {
		vkc.graphics_queue_idx = u32(graphics_idx)
		vkc.present_queue_idx = u32(present_idx)
		return true
	}
	return false
}
