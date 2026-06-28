/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.
*/

#include <LindChain/ProcEnvironment/Surface/entitlement.h>
#include <LindChain/ProcEnvironment/Surface/trust.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

kern_return_t entitlement_token_mach_gen(ksurface_ent_blob_t *blob,
                                         const char *cdhash,
                                         PEEntitlement entitlement)
{
    if(blob == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }

    bzero(blob, sizeof(*blob));
    blob->entitlement = entitlement;
    if(cdhash != NULL)
    {
        memcpy((void *)(blob->cdhash), cdhash, USER_FSIGNATURES_CDHASH_LEN);
    }
    return KERN_SUCCESS;
}

kern_return_t entitlement_mach_verify(ksurface_ent_result_t *mach)
{
    if(mach == NULL)
    {
        return KERN_INVALID_ARGUMENT;
    }
    return mach->cdhash_valid ? KERN_SUCCESS : KERN_DENIED;
}

PEEntitlement entitlement_get_path(const char *path,
                                   bool *wasLocallySigned)
{
    if(wasLocallySigned != NULL)
    {
        *wasLocallySigned = false;
    }

    int fd = open(path, O_RDONLY);
    if(fd < 0)
    {
        return PEEntitlementNone;
    }

    ksurface_ent_result_t mach;
    int ret = macho_read_token(fd, &mach);
    close(fd);

    if(ret != 0 || entitlement_mach_verify(&mach) != KERN_SUCCESS)
    {
        return PEEntitlementNone;
    }

    if(wasLocallySigned != NULL)
    {
        *wasLocallySigned = true;
    }
    return mach.blob.entitlement;
}

bool entitlement_set_path(const char *path,
                          PEEntitlement entitlement)
{
    int fd = open(path, O_RDWR);
    if(fd < 0)
    {
        return false;
    }

    int retval = macho_after_sign_fd(fd, entitlement);
    fsync(fd);
    close(fd);

    return (retval == 0);
}
