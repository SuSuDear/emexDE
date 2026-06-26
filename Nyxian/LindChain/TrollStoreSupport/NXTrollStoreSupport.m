#import "NXTrollStoreSupport.h"
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <string.h>
#import <unistd.h>

static NSString * const NXTrollStoreSupportErrorDomain = @"com.cr4zy.nyxian.trollstoresupport";
static NSString * const NXLdidDownloadURLString = @"https://github.com/opa334/ldid/releases/latest/download/ldid";

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

+ (NSString *)fallbackLdidPath
{
    NSURL *applicationSupportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[applicationSupportURL URLByAppendingPathComponent:@"ldid"].path copy];
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
    
    NSString *fallbackPath = [self fallbackLdidPath];
    if ([self ldidExistsAtPath:fallbackPath]) {
        chmod(fallbackPath.fileSystemRepresentation, 0755);
        return fallbackPath;
    }
    
    NSURL *downloadURL = [NSURL URLWithString:NXLdidDownloadURLString];
    NSData *ldidData = [NSData dataWithContentsOfURL:downloadURL options:0 error:error];
    if (!ldidData) {
        return nil;
    }
    
    NSArray<NSString *> *installPaths = @[preferredPath, fallbackPath];
    NSError *lastError = nil;
    for (NSString *installPath in installPaths) {
        NSString *directoryPath = installPath.stringByDeletingLastPathComponent;
        [NSFileManager.defaultManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager removeItemAtPath:installPath error:nil];
        if ([ldidData writeToFile:installPath options:NSDataWritingAtomic error:&lastError]) {
            chmod(installPath.fileSystemRepresentation, 0755);
            return installPath;
        }
    }
    
    if (error) {
        *error = lastError ?: [self errorWithCode:2 description:@"Failed to install downloaded ldid"];
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

+ (BOOL)signExecutableAtPath:(NSString *)executablePath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error
{
    NSString *ldidPath = [self ensureLdidInstalledWithError:error];
    if (!ldidPath) {
        return NO;
    }
    
    NSString *signArgument = [@"-S" stringByAppendingString:entitlementsPath];
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

@end
