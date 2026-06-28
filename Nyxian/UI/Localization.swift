/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2026 emexlab

 This file is part of Nyxian.
*/

import Foundation

@inline(__always)
func L10n(_ key: String, _ comment: String = "") -> String {
    NSLocalizedString(key, comment: comment)
}
