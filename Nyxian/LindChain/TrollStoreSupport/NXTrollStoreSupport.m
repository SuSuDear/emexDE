#import "NXTrollStoreSupport.h"
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <string.h>
#import <unistd.h>
#import <stdint.h>
#import <stdio.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)registerApplicationDictionary:(NSDictionary *)dictionary;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
@end

@interface MCMContainer : NSObject
+ (id)containerWithIdentifier:(id)identifier createIfNecessary:(BOOL)create existed:(BOOL *)existed error:(NSError **)error;
@property (nonatomic, readonly) NSURL *url;
@end

static BOOL NXIsMachOFile(NSString *path)
{
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    if (!file) {
        return NO;
    }

    uint32_t magic = 0;
    fread(&magic, sizeof(uint32_t), 1, file);
    fclose(file);

    return magic == 0xfeedfacf || magic == 0xcffaedfe || magic == 0xcafebabe || magic == 0xbebafeca;
}

static NSString * const NXTrollStoreSupportErrorDomain = @"com.cr4zy.nyxian.trollstoresupport";
static NSString * const NXLdidDownloadURLString = @"https://github.com/opa334/ldid/releases/latest/download/ldid";
static NSString * const NXTrollStoreMarkerName = @"_TrollStore";

@implementation NXTrollStoreSupport

+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
    return [NSError errorWithDomain:NXTrollStoreSupportErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description ?: @"Unknown TrollStore support error"}];
}

+ (nullable NSString *)projectEntitlementsPathForProjectPath:(NSString *)projectPath error:(NSError **)error
{
    NSArray<NSString *> *candidates = @[
        [projectPath stringByAppendingPathComponent:@"Config/Entitlements.plist"],
        [projectPath stringByAppendingPathComponent:@"Config/entitlements.plist"]
    ];

    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *candidate in candidates) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
            return candidate;
        }
    }

    if (error) {
        *error = [self errorWithCode:1 description:@"Missing project Config/Entitlements.plist or Config/entitlements.plist"];
    }
    return nil;
}

+ (NSString *)preferredLdidPath
{
    return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ldid"];
}

+ (BOOL)ldidExistsAtPath:(NSString *)path
{
    BOOL isDirectory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory;
}

+ (nullable NSString *)ensureLdidInstalledWithError:(NSError **)error
{
    NSString *preferredPath = [self preferredLdidPath];
    if ([self ldidExistsAtPath:preferredPath]) {
        chmod(preferredPath.fileSystemRepresentation, 0755);
        return preferredPath;
    }

    NSURL *downloadURL = [NSURL URLWithString:NXLdidDownloadURLString];
    NSData *ldidData = [NSData dataWithContentsOfURL:downloadURL options:0 error:error];
    if (!ldidData) {
        return nil;
    }

    [NSFileManager.defaultManager removeItemAtPath:preferredPath error:nil];
    if ([ldidData writeToFile:preferredPath options:NSDataWritingAtomic error:error]) {
        chmod(preferredPath.fileSystemRepresentation, 0755);
        return preferredPath;
    }

    return nil;
}

+ (NSString *)stringFromFileDescriptor:(int)fd
{
    NSMutableData *data = [NSMutableData data];
    char buffer[4096];
    ssize_t bytesRead = 0;
    while ((bytesRead = read(fd, buffer, sizeof(buffer))) > 0) {
        [data appendBytes:buffer length:(NSUInteger)bytesRead];
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

+ (nullable NSDictionary *)infoDictionaryForAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    if (![infoDictionary isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [self errorWithCode:6 description:@"The app bundle is missing Info.plist"];
        }
        return nil;
    }

    NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];
    NSString *executableName = infoDictionary[@"CFBundleExecutable"];
    if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0 ||
        ![executableName isKindOfClass:NSString.class] || executableName.length == 0) {
        if (error) {
            *error = [self errorWithCode:6 description:@"The app bundle Info.plist is missing required values"];
        }
        return nil;
    }
    return infoDictionary;
}

+ (BOOL)copyItemReplacingExistingPath:(NSString *)sourcePath toPath:(NSString *)destinationPath error:(NSError **)error
{
    [NSFileManager.defaultManager removeItemAtPath:destinationPath error:nil];
    return [NSFileManager.defaultManager copyItemAtPath:sourcePath toPath:destinationPath error:error];
}

+ (BOOL)fixPermissionsForAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    NSDirectoryEnumerator<NSString *> *enumerator = [NSFileManager.defaultManager enumeratorAtPath:bundlePath];
    for (NSString *relativePath in enumerator) {
        NSString *path = [bundlePath stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
        NSDictionary *attributes = @{NSFilePosixPermissions: @(isDirectory || NXIsMachOFile(path) ? 0755 : 0644)};
        if (![NSFileManager.defaultManager setAttributes:attributes ofItemAtPath:path error:error]) {
            return NO;
        }
        chown(path.fileSystemRepresentation, 33, 33);
    }
    chown(bundlePath.fileSystemRepresentation, 33, 33);
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:bundlePath error:error];
}

+ (BOOL)installAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = [self errorWithCode:7 description:@"Missing app bundle for TrollStore installation"];
        }
        return NO;
    }

    NSDictionary *infoDictionary = [self infoDictionaryForAppBundleAtPath:bundlePath error:error];
    if (!infoDictionary) {
        return NO;
    }
    NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];

    Class appContainerClass = NSClassFromString(@"MCMAppContainer");
    Class appDataContainerClass = NSClassFromString(@"MCMAppDataContainer");
    if (!appContainerClass || !appDataContainerClass) {
        if (error) {
            *error = [self errorWithCode:8 description:@"MobileContainerManager classes are unavailable"];
        }
        return NO;
    }

    NSError *containerError = nil;
    MCMContainer *appContainer = [appContainerClass containerWithIdentifier:bundleIdentifier createIfNecessary:YES existed:nil error:&containerError];
    if (!appContainer || containerError) {
        if (error) {
            *error = containerError ?: [self errorWithCode:8 description:@"Failed to create app container"];
        }
        return NO;
    }

    MCMContainer *dataContainer = [appDataContainerClass containerWithIdentifier:bundleIdentifier createIfNecessary:YES existed:nil error:nil];
    NSString *dataContainerPath = dataContainer.url.path;
    if (dataContainerPath.length) {
        [NSFileManager.defaultManager createDirectoryAtPath:[dataContainerPath stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *markerPath = [appContainer.url.path stringByAppendingPathComponent:NXTrollStoreMarkerName];
    if (![NSFileManager.defaultManager fileExistsAtPath:markerPath]) {
        [NSData.data writeToFile:markerPath atomically:NO];
    }

    NSString *destinationPath = [appContainer.url.path stringByAppendingPathComponent:bundlePath.lastPathComponent];
    NSError *copyError = nil;
    if (![self copyItemReplacingExistingPath:bundlePath toPath:destinationPath error:&copyError]) {
        if (error) {
            *error = copyError ?: [self errorWithCode:9 description:@"Failed to copy app bundle into app container"];
        }
        return NO;
    }

    NSError *permissionError = nil;
    if (![self fixPermissionsForAppBundleAtPath:destinationPath error:&permissionError]) {
        if (error) {
            *error = permissionError ?: [self errorWithCode:10 description:@"Failed to fix app bundle permissions"];
        }
        return NO;
    }

    NSMutableDictionary *registration = [NSMutableDictionary dictionary];
    registration[@"ApplicationType"] = @"System";
    registration[@"CFBundleIdentifier"] = bundleIdentifier;
    registration[@"CodeInfoIdentifier"] = bundleIdentifier;
    registration[@"CompatibilityState"] = @0;
    registration[@"IsContainerized"] = @YES;
    if (dataContainerPath.length) {
        registration[@"Container"] = dataContainerPath;
        registration[@"EnvironmentVariables"] = @{
            @"CFFIXED_USER_HOME": dataContainerPath,
            @"HOME": dataContainerPath,
            @"TMPDIR": [dataContainerPath stringByAppendingPathComponent:@"tmp"]
        };
    }
    registration[@"IsDeletable"] = @YES;
    registration[@"Path"] = destinationPath;
    registration[@"SignerOrganization"] = @"Apple Inc.";
    registration[@"SignatureVersion"] = @132352;
    registration[@"SignerIdentity"] = @"Apple iPhone OS Application Signing";
    registration[@"IsAdHocSigned"] = @YES;
    registration[@"LSInstallType"] = @1;
    registration[@"HasMIDBasedSINF"] = @0;
    registration[@"MissingSINF"] = @0;
    registration[@"FamilyID"] = @0;
    registration[@"IsOnDemandInstallCapable"] = @0;

    @try {
        if (![[LSApplicationWorkspace defaultWorkspace] registerApplicationDictionary:registration]) {
            if (error) {
                *error = [self errorWithCode:11 description:@"Failed to register installed app"];
            }
            return NO;
        }
    } @catch (NSException *exception) {
        if (error) {
            *error = [self errorWithCode:11 description:[NSString stringWithFormat:@"Register app failed: %@", exception.reason ?: exception.name]];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)signExecutableAtPath:(NSString *)executablePath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error
{
    NSString *ldidPath = [self ensureLdidInstalledWithError:error];
    if (!ldidPath) {
        return NO;
    }

    NSString *temporaryEntitlementsPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"ldid-entitlements-%@.plist", NSUUID.UUID.UUIDString]];
    if (![NSFileManager.defaultManager copyItemAtPath:entitlementsPath toPath:temporaryEntitlementsPath error:error]) {
        return NO;
    }
    chmod(temporaryEntitlementsPath.fileSystemRepresentation, 0644);

    NSString *signArgument = [@"-S" stringByAppendingString:temporaryEntitlementsPath];
    NSArray<NSString *> *arguments = @[ldidPath.lastPathComponent, signArgument, executablePath];

    char **argv = calloc(arguments.count + 1, sizeof(char *));
    for (NSUInteger index = 0; index < arguments.count; index++) {
        argv[index] = strdup(arguments[index].UTF8String);
    }
    argv[arguments.count] = NULL;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    int stderrPipe[2];
    pipe(stderrPipe);
    posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);

    pid_t pid = 0;
    int spawnError = posix_spawn(&pid, ldidPath.fileSystemRepresentation, &actions, NULL, argv, NULL);

    for (NSUInteger index = 0; index < arguments.count; index++) {
        free(argv[index]);
    }
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(stderrPipe[1]);

    NSString *stderrOutput = [self stringFromFileDescriptor:stderrPipe[0]];
    close(stderrPipe[0]);
    [NSFileManager.defaultManager removeItemAtPath:temporaryEntitlementsPath error:nil];

    if (spawnError != 0) {
        if (error) {
            *error = [self errorWithCode:3 description:[NSString stringWithFormat:@"Failed to spawn ldid: %s", strerror(spawnError)]];
        }
        return NO;
    }

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) {
        if (error) {
            *error = [self errorWithCode:4 description:@"Failed to wait for ldid"];
        }
        return NO;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (error) {
            *error = [self errorWithCode:5 description:[NSString stringWithFormat:@"ldid failed: %@", stderrOutput.length ? stderrOutput : @"unknown error"]];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error
{
    if (bundleIdentifier.length == 0) {
        if (error) {
            *error = [self errorWithCode:9 description:@"Missing bundle identifier"];
        }
        return NO;
    }

    for (NSInteger attempt = 0; attempt < 10; attempt++) {
        if ([[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:bundleIdentifier]) {
            return YES;
        }
        [NSThread sleepForTimeInterval:0.5];
    }

    if (error) {
        *error = [self errorWithCode:10 description:@"Installed app but failed to open it"];
    }
    return NO;
}

@end
