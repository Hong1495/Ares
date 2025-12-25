import Foundation

// Simulation of ConfigService.injectMITMConfig logic for verification

func injectMITMConfig(into yaml: String, mitmPort: Int) -> String {
    var result = yaml
    
    // 1. Inject MITM proxy after "proxies:" line
    let mitmProxy = """
      - name: MITM-Intercept
        type: http
        server: 127.0.0.1
        port: \(mitmPort)
    """
    
    // Find "proxies:" and insert after it
    if let proxiesRange = result.range(of: "proxies:", options: .caseInsensitive) {
        // Find the end of the line
        if let lineEnd = result[proxiesRange.upperBound...].firstIndex(of: "\n") {
            result.insert(contentsOf: "\n" + mitmProxy, at: lineEnd)
        }
    }
    
    // 2. Inject MITM rules at the beginning of "rules:" section
    let mitmRules = """
      - DST-PORT,\(mitmPort),DIRECT
      - AND,((DST-PORT,80),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept
      - AND,((DST-PORT,443),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept
      - AND,((DST-PORT,8080),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept
      - AND,((DST-PORT,8443),(NOT,((PROCESS-NAME,Ares)))),MITM-Intercept
    """
    
    // Find "rules:" and insert after it
    if let rulesRange = result.range(of: "rules:", options: .caseInsensitive) {
        if let lineEnd = result[rulesRange.upperBound...].firstIndex(of: "\n") {
            result.insert(contentsOf: "\n" + mitmRules, at: lineEnd)
        }
    }
    
    return result
}

// Test Data
let sampleYAML = """
port: 7890
proxies:
  - name: Shadow
    type: ss
rules:
  - MATCH,DIRECT
"""

print("--- Original ---")
print(sampleYAML)

print("\n--- Injected ---")
let injected = injectMITMConfig(into: sampleYAML, mitmPort: 9090)
print(injected)

print("\n--- Verification ---")
if injected.contains("PROCESS-NAME,Ares") {
    print("✅ SUCCESS: Ares process exclusion rule found.")
} else {
    print("❌ FAILURE: Ares process exclusion rule MISSING.")
    exit(1)
}

if injected.contains("MITM-Intercept") {
    print("✅ SUCCESS: MITM-Intercept proxy found.")
} else {
    print("❌ FAILURE: MITM-Intercept proxy MISSING.")
    exit(1)
}
