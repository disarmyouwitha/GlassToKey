import Foundation
import Security
import ServiceManagement

enum VirtualHIDHelperInstaller {
    private static let helperLabel = VirtualHIDHelperMachServiceName

    static func installIfNeeded(
        completion: @escaping (Bool, String?) -> Void
    ) {
        if isHelperInstalled() {
            completion(true, nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var authRef: AuthorizationRef?
            let status = AuthorizationCreate(
                nil,
                nil,
                AuthorizationFlags([.interactionAllowed, .extendRights, .preAuthorize]),
                &authRef
            )
            guard status == errAuthorizationSuccess, let authRef else {
                completion(false, "Authorization failed")
                return
            }
            var error: Unmanaged<CFError>?
            let blessed = SMJobBless(
                kSMDomainSystemLaunchd,
                helperLabel as CFString,
                authRef,
                &error
            )
            AuthorizationFree(authRef, [])
            if blessed {
                completion(true, nil)
            } else {
                let message = error?.takeRetainedValue().localizedDescription
                    ?? "SMJobBless failed"
                completion(false, message)
            }
        }
    }

    static func isHelperInstalled() -> Bool {
        guard let job = SMJobCopyDictionary(
            kSMDomainSystemLaunchd,
            helperLabel as CFString
        ) else {
            return false
        }
        job.takeRetainedValue()
        return true
    }
}
