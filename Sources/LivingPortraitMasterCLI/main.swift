import Darwin
import Foundation
import LivingPortraitAuthoring

@main
enum LivingPortraitMasterCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeError("living-portrait-master: \(error)\n")
            Darwin.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        if arguments.isEmpty || (arguments.count == 1 && ["help", "--help", "-h"].contains(arguments[0])) {
            print(usage)
            return
        }

        switch arguments[0] {
        case "init" where arguments.count == 2:
            let workspaceURL = fileURL(arguments[1])
            try LivingPortraitAuthoringWorkspace.scaffold(at: workspaceURL)
            print("created workspace: \(workspaceURL.path)")
            print("next: add source and asset files, then edit job.json, candidate.json, and measurements.json")

        case "validate" where arguments.count == 2:
            let checks = try LivingPortraitAuthoringWorkspace.validate(at: fileURL(arguments[1]))
            print("valid workspace: \(checks.sorted().joined(separator: ", "))")

        case "keygen" where arguments.count == 5:
            guard arguments[4] == "--acknowledge-private-key" else { throw CLIError.invalidArguments }
            let documents = try LivingPortraitAuthoringWorkspace.generateSigningKeyDocuments(keyID: arguments[1])
            let privateKeyURL = fileURL(arguments[2])
            let publicKeyURL = fileURL(arguments[3])
            try LivingPortraitAuthoringWorkspace.writeKeyDocuments(
                privateKey: documents.privateKey,
                publicKey: documents.publicKey,
                privateKeyURL: privateKeyURL,
                publicKeyURL: publicKeyURL
            )
            print("created private key (0600): \(privateKeyURL.path)")
            print("created public key: \(publicKeyURL.path)")

        case "bake" where arguments.count == 8:
            guard arguments[2] == "--approved-by",
                  arguments[4] == "--private-key",
                  arguments[6] == "--output" else {
                throw CLIError.invalidArguments
            }
            let privateKey: LivingPortraitPrivateKeyDocument = try readJSON(at: fileURL(arguments[5]))
            let baked = try LivingPortraitAuthoringWorkspace.bake(
                workspaceAt: fileURL(arguments[1]),
                approvedBy: arguments[3],
                privateKeyDocument: privateKey
            )
            let outputURL = fileURL(arguments[7])
            try LivingPortraitAuthoringWorkspace.writePackage(baked, to: outputURL)
            print("baked signed package: \(outputURL.path)")

        case "verify" where arguments.count == 4:
            guard arguments[2] == "--public-key" else { throw CLIError.invalidArguments }
            let publicKey: LivingPortraitPublicKeyDocument = try readJSON(at: fileURL(arguments[3]))
            let package = try LivingPortraitAuthoringWorkspace.verifyPackage(
                at: fileURL(arguments[1]),
                publicKeyDocument: publicKey
            )
            print("verified package: \(package.manifest.packageID) revision \(package.manifest.revision)")
            print("scene: \(package.scene.id), files: \(package.manifest.files.count)")

        case "validate-provider-config" where arguments.count == 2:
            let configuration: LivingPortraitProviderConfiguration = try readJSON(at: fileURL(arguments[1]))
            try configuration.validateNoEmbeddedSecret()
            print("valid provider configuration: \(configuration.id)")

        default:
            writeError("\(usage)\n")
            throw CLIError.invalidArguments
        }
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func readJSON<Value: Decodable>(at url: URL) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private static let usage = """
    Usage:
      living-portrait-master init <workspace>
      living-portrait-master validate <workspace>
      living-portrait-master keygen <key-id> <private-key.json> <public-key.json> --acknowledge-private-key
      living-portrait-master bake <workspace> --approved-by <name> --private-key <private-key.json> --output <package-dir>
      living-portrait-master verify <package-dir> --public-key <public-key.json>
      living-portrait-master validate-provider-config <configuration.json>

    `init` creates a fail-closed workspace template. Generation and independent measurements come
    from provider adapters; this tool validates, records explicit human approval, signs, and verifies.
    Existing workspaces, keys, and package directories are never overwritten.
    """

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    private enum CLIError: Error, CustomStringConvertible {
        case invalidArguments

        var description: String { "invalid arguments" }
    }
}
