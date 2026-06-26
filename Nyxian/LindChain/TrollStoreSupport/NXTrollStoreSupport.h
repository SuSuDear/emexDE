#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NXTrollStoreSupport : NSObject

+ (nullable NSString *)projectEntitlementsPathForProjectPath:(NSString *)projectPath error:(NSError **)error;
+ (nullable NSString *)ensureLdidInstalledWithError:(NSError **)error;
+ (BOOL)signExecutableAtPath:(NSString *)executablePath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
