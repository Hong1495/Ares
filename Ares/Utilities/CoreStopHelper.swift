import Foundation

/// A fixed, root-owned helper. No caller-supplied PID, command, or path is accepted.
nonisolated enum CoreStopHelper {
    static func path(userID: UInt32) -> String {
        "/Library/PrivilegedHelperTools/studio.hera.ares.stop-\(userID)"
    }

    static func script(support: URL, userID: UInt32) -> String {
        let quote = CoreProcessIdentity.shellQuote
        return """
        #!/bin/sh
        set -eu
        [ "$#" -eq 0 ] || exit 64
        [ "${SUDO_UID:-}" = "\(userID)" ] || exit 77
        support=\(quote(support.path))
        for pid in $(/bin/ps -axo pid=); do
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            [ "$pid" -gt 1 ] || continue
            uid=$(/bin/ps -p "$pid" -o uid= 2>/dev/null | /usr/bin/tr -d ' ') || continue
            [ "$uid" = 0 ] || [ "$uid" = "\(userID)" ] || continue
            command=$(/bin/ps -ww -p "$pid" -o command= 2>/dev/null) || continue
            case "$command" in '/usr/bin/sudo -n '*) command=${command#'/usr/bin/sudo -n '} ;; esac
            binary=''
            for directory in clash clash_user clash_root; do
                suffix=" -d $support/$directory"
                case "$command" in *"$suffix") binary=${command%"$suffix"}; break ;; esac
            done
            case "$binary" in
                "$support/Core/mihomo") ;;
                /*/Ares.app/Contents/Resources/clash-meta) ;;
                *) continue ;;
            esac
            case "$binary" in *' -'*) continue ;; esac
            expected=$(/bin/ps -ww -p "$pid" -o lstart=,command= 2>/dev/null) || continue
            # Ensure the process command has not changed during discovery.
            actual=$(/bin/ps -ww -p "$pid" -o command= 2>/dev/null) || continue
            case "$actual" in '/usr/bin/sudo -n '*) actual=${actual#'/usr/bin/sudo -n '} ;; esac
            [ "$actual" = "$command" ] || continue
            matches() { [ "$(/bin/ps -ww -p "$pid" -o lstart=,command= 2>/dev/null || true)" = "$expected" ]; }
            if matches; then
                /bin/kill -TERM "$pid" 2>/dev/null || true
                n=0
                while matches && [ "$n" -lt 30 ]; do /bin/sleep 0.1; n=$((n+1)); done
                if matches; then /bin/kill -KILL "$pid" 2>/dev/null || true; fi
            fi
        done
        """
    }
}
