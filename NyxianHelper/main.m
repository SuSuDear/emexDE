#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <spawn.h>

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict, uid_t);
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>

static NSString *NXStringFromFileDescriptor(int fd)
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

static int NXRunLdid(NSString *ldidPath, NSArray<NSString *> *arguments)
{
    NSMutableArray<NSString *> *allArguments = arguments.mutableCopy;
    [allArguments insertObject:ldidPath.lastPathComponent atIndex:0];

    char **argv = calloc(allArguments.count + 1, sizeof(char *));
    for (NSUInteger index = 0; index < allArguments.count; index++) {
        argv[index] = strdup(allArguments[index].UTF8String);
    }
    argv[allArguments.count] = NULL;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    int stderrPipe[2];
    pipe(stderrPipe);
    posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attributes, 0);
    posix_spawnattr_set_persona_gid_np(&attributes, 0);

    pid_t pid = 0;
    int spawnError = posix_spawn(&pid, ldidPath.fileSystemRepresentation, &actions, &attributes, argv, NULL);
    posix_spawnattr_destroy(&attributes);

    for (NSUInteger index = 0; index < allArguments.count; index++) {
        free(argv[index]);
    }
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(stderrPipe[1]);

    NSString *stderrOutput = NXStringFromFileDescriptor(stderrPipe[0]);
    close(stderrPipe[0]);

    if (spawnError != 0) {
        fprintf(stderr, "Failed to spawn ldid: %s\n", strerror(spawnError));
        return spawnError;
    }

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) {
        fprintf(stderr, "Failed to wait for ldid\n");
        return 255;
    }

    if (stderrOutput.length > 0) {
        fprintf(stderr, "%s", stderrOutput.UTF8String);
    }

    if (!WIFEXITED(status)) {
        return 254;
    }
    return WEXITSTATUS(status);
}

static int NXSignExecutable(NSString *ldidPath, NSString *entitlementsPath, NSString *executablePath)
{
    NSString *temporaryEntitlementsPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByAppendingPathExtension:@"plist"];
    NSError *copyError = nil;
    if (![NSFileManager.defaultManager copyItemAtPath:entitlementsPath toPath:temporaryEntitlementsPath error:&copyError]) {
        fprintf(stderr, "Failed to copy entitlements: %s\n", copyError.localizedDescription.UTF8String);
        return 2;
    }
    chmod(temporaryEntitlementsPath.fileSystemRepresentation, 0644);

    NSString *signArgument = [@"-S" stringByAppendingString:temporaryEntitlementsPath];
    int result = NXRunLdid(ldidPath, @[signArgument, executablePath]);
    [NSFileManager.defaultManager removeItemAtPath:temporaryEntitlementsPath error:nil];
    return result;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 5 || strcmp(argv[1], "sign") != 0) {
            fprintf(stderr, "Usage: %s sign <ldid> <entitlements.plist> <executable>\n", argv[0]);
            return 1;
        }

        NSString *ldidPath = [NSString stringWithUTF8String:argv[2]];
        NSString *entitlementsPath = [NSString stringWithUTF8String:argv[3]];
        NSString *executablePath = [NSString stringWithUTF8String:argv[4]];
        if (!ldidPath || !entitlementsPath || !executablePath) {
            fprintf(stderr, "Invalid arguments\n");
            return 1;
        }

        chmod(ldidPath.fileSystemRepresentation, 0755);
        return NXSignExecutable(ldidPath, entitlementsPath, executablePath);
    }
}
