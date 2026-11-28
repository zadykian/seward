import CryptoKit
import Foundation

extension Agent {
    /// The agent of the context's keys: those of seward's files in its keys' directory, each
    /// loaded from its store at each request.
    init(context: Context, log: any AgentLog) {
        self.init(
            keys: {
                AgentKeyFiles.keys(in: context.keys, log: log) { name, file in
                    let key = try SigningKey.load(file, enclave: context.enclave)
                    return AgentKey(name: name.value, blob: SSHPublicKey(key.publicKey).blob) { data in
                        try key.signature(for: data).rawRepresentation
                    }
                }
            }, log: log)
    }
}
