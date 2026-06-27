/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import "LDEApplicationObject.h"
#import "ISIcon.h"
#import <LindChain/Private/UIKitPrivate.h>

#import <UIKit/UIKit.h>

@implementation LDEApplicationObject

- (instancetype)initWithNSBundle:(NSBundle*)bundle
{
#if HOST_ENV
    return nil;
#else
    self = [super init];
    
    self.bundleIdentifier = bundle.bundleIdentifier;
    
    NSString *localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(!localizedDisplayName)
    {
        localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    }
    self.localizedName = NSLocalizedStringFromTableInBundle(localizedDisplayName, @"InfoPlist", bundle, localizedDisplayName);
    self.bundlePath = [[bundle bundleURL] path];
    self.executablePath = [[bundle executableURL] path];
    
    ISBundleIcon *bundleIcon = [[PrivClass(ISBundleIcon) alloc] initWithBundleURL:bundle.bundleURL type:nil];
    if(bundleIcon)
    {
        ISResourceProvider *provider = [bundleIcon _makeAppResourceProvider];
        if(provider.isGenericProvider) return self;
        
        ISAssetCatalogResource *resources = [provider iconResource];
        if ([resources isKindOfClass:NSClassFromString(@"IFImageBag")])
        {
            IFImageBag *imageBag = (IFImageBag*)resources;
            IFImage *image = [imageBag imageForSize:CGSizeMake(1024, 1024) scale:3.0];
            self.icon = [UIImage imageWithCGImage:image.CGImage scale:3.0 orientation:UIImageOrientationUp];
            return self;
        }
        
        IFImage *image = [resources imageForSize:CGSizeMake(1024, 1024) scale:3.0];
        self.icon = [UIImage imageWithCGImage:image.CGImage scale:3.0 orientation:UIImageOrientationUp];
    }

    return self;
#endif /* HOST_ENV */
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder
{
    [coder encodeObject:self.bundleIdentifier forKey:@"bundleIdentifier"];
    [coder encodeObject:self.bundlePath forKey:@"bundlePath"];
    [coder encodeObject:self.executablePath forKey:@"executablePath"];
    [coder encodeObject:self.localizedName forKey:@"localizedName"];
    [coder encodeObject:self.icon forKey:@"icon"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder
{
    if(self = [super init])
    {
        _bundleIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"bundleIdentifier"];
        _bundlePath = [coder decodeObjectOfClass:[NSString class] forKey:@"bundlePath"];
        _executablePath = [coder decodeObjectOfClass:[NSString class] forKey:@"executablePath"];
        _localizedName = [coder decodeObjectOfClass:[NSString class] forKey:@"localizedName"];
        _icon = [coder decodeObjectOfClass:[UIImage class] forKey:@"icon"];
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[LDEApplicationObject class]]) return NO;
    LDEApplicationObject *other = (LDEApplicationObject *)object;
    return [self.bundleIdentifier isEqualToString:other.bundleIdentifier];
}

- (NSUInteger)hash
{
    return self.bundleIdentifier.hash;
}

@end
