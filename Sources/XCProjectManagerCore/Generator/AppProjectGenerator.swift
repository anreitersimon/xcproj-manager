import Foundation
import XcodeGenKit
import ProjectSpec
import JSONUtilities
import PathKit
import Yams
import xcproj

public class AppProjectGenerator {
    public typealias DependencyResolver = (AppSpec) throws -> [Dependency]
    
    public let spec: AppSpec
    public let projectPath: Path
    
    var dependencyResolver: DependencyResolver
    
    var filesystem: FileSystem = DefaultFileSystem()
    
    public init(
        spec: AppSpec,
        projectPath: Path,
        dependencyResolver: @escaping DependencyResolver
    ) {
        self.spec = spec
        self.projectPath = projectPath
        self.dependencyResolver = dependencyResolver
    }
    
    var directory: Path {
        return self.projectPath.parent()
    }
    
    func generateMainTargetFiles() throws {
        let root = self.directory + self.spec.targetName
        let sources = root + "Sources"
        let resources = root + "Resources"
        let config = root + "Config"
        
        let generator = FileGenerator(filesystem: self.filesystem)
        
        try generator.generateDirectories([
            root,
            sources,
            resources,
            config
        ])
        
        try generator.generateFiles([
            root + "Info.plist": Plist.app(),
            sources + "Dependencies.swift": SourceFile.dependencies(feature: self.spec.name),
            sources + "AppDelegate.swift": SourceFile.appdelegate()
        ])
        
    }
    
    func generateUITestFiles() throws {
        let root = self.directory + self.spec.uiTestTargetName
        let sources = root + "Sources"
        let resources = root + "Resources"
        let config = root + "Config"
        
        let generator = FileGenerator(filesystem: self.filesystem)
        
        try generator.generateDirectories([
            root,
            sources,
            resources,
            config
        ])
        
        try generator.generateFiles([
            root + "Info.plist": Plist.appUITests()
        ])
        
    }
    
    func generateUnitTestFiles() throws {
        let root = self.directory + self.spec.unitTestTargetName
        let sources = root + "Sources"
        let resources = root + "Resources"
        let config = root + "Config"
        
        let generator = FileGenerator(filesystem: self.filesystem)
        
        try generator.generateDirectories([
            root,
            sources,
            resources,
            config
        ])
        
        try generator.generateFiles([
            root + "Info.plist": Plist.appUnitTests()
        ])
        
    }
    
    func scaffold() throws {
        try self.generateMainTargetFiles()
        try self.generateUnitTestFiles()
        try self.generateUITestFiles()
    }
    
    public func generate() throws {
        let project = try generateProject()
        
        try project.write(path: self.projectPath)
    }
    
    func generateAppTarget() throws -> Target {
        
        let dependencies = try self.generateDependencies()
        
        return Target(
            name: self.spec.targetName,
            type: .application,
            platform: .iOS,
            sources: [
                TargetSource(path: self.spec.targetName)
            ],
            dependencies: dependencies,
            prebuildScripts: [],
            postbuildScripts: [],
            scheme: TargetScheme(
                testTargets: [
                    self.spec.unitTestTargetName,
                    self.spec.uiTestTargetName
                ],
                gatherCoverageData: true,
                commandLineArguments: [:]
            ),
            legacy: nil
        )
        
    }
    
    
    func generateUnitTestTarget() throws -> Target {
        
        let dependencies = try self.generateDependencies()
        
        return Target(
            name: self.spec.unitTestTargetName,
            type: .unitTestBundle,
            platform: .iOS,
            sources: [
                TargetSource(path: self.spec.unitTestTargetName)
            ],
            dependencies: dependencies,
            prebuildScripts: [],
            postbuildScripts: [],
            scheme: TargetScheme(
                testTargets: [],
                gatherCoverageData: true,
                commandLineArguments: [:]
            ),
            legacy: nil
        )
        
    }
    
    func generateUITestTarget() throws -> Target {
        
        let dependencies = try self.generateDependencies()
        
        return Target(
            name: self.spec.uiTestTargetName,
            type: .uiTestBundle,
            platform: .iOS,
            sources: [
                TargetSource(path: self.spec.uiTestTargetName)
            ],
            dependencies: dependencies,
            prebuildScripts: [],
            postbuildScripts: [],
            scheme: TargetScheme(
                testTargets: [],
                gatherCoverageData: true,
                commandLineArguments: [:]
            ),
            legacy: nil
        )
        
    }
    
    func generateProject() throws -> XcodeProj {
        
        
        let spec = ProjectSpec(
            basePath: self.directory,
            name: self.spec.name,
            configs: [
                Config(name: "Debug", type: .debug),
                Config(name: "Distribution", type: .release),
                Config(name: "Release", type: .release),
                ],
            targets: [
                try generateAppTarget(),
                try generateUnitTestTarget(),
                try generateUITestTarget()
            ],
            settings: Settings(
                buildSettings: [:],
                configSettings: [:],
                groups: []
            ),
            settingGroups: [:],
            schemes: [],
            options: .init(
                carthageBuildPath: "../Carthage/Build",
                bundleIdPrefix: "at.imobility"
            ),
            fileGroups: [],
            configFiles: [:],
            attributes: [:]
        )
        
        let generator = ProjectGenerator(
            spec: spec
        )
        
        return try generator.generateProject()
    }
    
    func generateDependencies() throws -> [Dependency] {
        return try dependencyResolver(self.spec)
    }
}


extension WorkspaceGenerator {
    
    func feature(for name: String) -> FeatureSpec? {
        return self.spec.features.first { $0.name == name }
    }
    
    func carthage(for name: String) -> FeatureSpec? {
        return self.spec.features.first { $0.name == name }
    }
    
    func flattenedCarthageDependencies(feature: FeatureSpec) -> Set<String>  {
        var result = Set<String>(feature.carthageDependencies ?? [])
        
        
        let deps = feature.dependencies ?? []
        let subFeatures = deps.flatMap { self.feature(for: $0) }
        
        for f in subFeatures {
            result.formUnion(self.flattenedCarthageDependencies(feature: f))
        }
        
        return result
    }
    
    func generateAppDependencies(_ app: AppSpec) -> [Dependency] {
        
        let deps = app.dependencies ?? []
        
        let subFeatures = deps.flatMap { self.feature(for: $0) }
        
        var carthageDepNames = Set<String>(app.carthageDependencies ?? [])
        
        for f in subFeatures {
            carthageDepNames.formUnion(self.flattenedCarthageDependencies(feature: f))
        }
        

        let carthageDeps = carthageDepNames.map {
            return Dependency(
                type: .carthage,
                reference: $0,
                embed: true,
                link: true,
                implicit: false
            )
        }
        
        var dependencies = subFeatures.map {
            return Dependency(
                type: .framework,
                reference: "\($0.name).framework",
                embed: true,
                link: true,
                implicit: true
            )
        }
        
        dependencies.append(contentsOf: carthageDeps)
        
        return dependencies
    }
    
}

