/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.
*/

#ifndef PROCENVIRONMENT_SURFACE_H
#define PROCENVIRONMENT_SURFACE_H

#ifdef __OBJC__
#import <Foundation/Foundation.h>
int ksurface_sethostname(NSString *hostname);
#endif /* __OBJC__ */

void ksurface_kinit(void);

#endif /* PROCENVIRONMENT_SURFACE_H */
