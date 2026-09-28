//
//  MacAddress.swift
//
//
//  Ported from ReaddleLib's RDGetMACAddressString.
//

#if os(macOS)
import Foundation
import IOKit
import IOKit.network

/// Reads the MAC address of the primary (built-in) network interface from the I/O Registry.
///
/// Unlike looking up "en0" through `sysctl(NET_RT_IFLIST)`, this keeps working on macOS 27, and does not
/// depend on which BSD name the primary interface has.
enum MacAddress {
    /// MAC address of the primary interface formatted as "ce:a9:3b:c0:ae:09", or nil when it can't be read.
    static func primaryInterface() -> String? {
        guard let bytes = primaryInterfaceBytes(),
              bytes.count >= kIOEthernetAddressSize,
              bytes.contains(where: { $0 != 0 })
        else {
            return nil
        }
        return bytes.prefix(Int(kIOEthernetAddressSize))
            .map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }

    private static func primaryInterfaceBytes() -> Data? {
        guard let iterator = findPrimaryEthernetInterfaces() else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        // The iterator should contain just the primary interface. If there are several, use the last one.
        var address: Data?
        var interface = IOIteratorNext(iterator)
        while interface != 0 {
            if let interfaceAddress = macAddress(ofInterface: interface) {
                address = interfaceAddress
            }
            IOObjectRelease(interface)
            interface = IOIteratorNext(iterator)
        }
        return address
    }

    /// Returns an iterator over Ethernet interfaces that have kIOPrimaryInterface set.
    /// The caller is responsible for releasing the iterator.
    private static func findPrimaryEthernetInterfaces() -> io_iterator_t? {
        guard let matchingDict = IOServiceMatching(kIOEthernetInterfaceClass) as NSMutableDictionary? else {
            return nil
        }
        // IONetworkingFamily defines no family-specific matching, so kIOPrimaryInterface has to be matched
        // through a nested kIOPropertyMatchKey dictionary.
        matchingDict[kIOPropertyMatchKey] = [kIOPrimaryInterface: true]

        var iterator: io_iterator_t = 0
        // MACH_PORT_NULL is the default main port (kIOMainPortDefault, which requires macOS 12).
        let result = IOServiceGetMatchingServices(mach_port_t(MACH_PORT_NULL), matchingDict as CFDictionary, &iterator)
        guard result == KERN_SUCCESS else {
            return nil
        }
        return iterator
    }

    private static func macAddress(ofInterface interface: io_object_t) -> Data? {
        // Network controllers don't participate in driver matching, so they can't be found directly.
        // Get the controller as the parent of the interface instead.
        var controller: io_object_t = 0
        guard IORegistryEntryGetParentEntry(interface, kIOServicePlane, &controller) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(controller) }

        let property = IORegistryEntryCreateCFProperty(
            controller,
            kIOMACAddress as CFString,
            kCFAllocatorDefault,
            0
        )
        return property?.takeRetainedValue() as? Data
    }
}
#endif
