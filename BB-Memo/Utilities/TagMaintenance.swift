//
//  TagMaintenance.swift
//  BB
//
//  Created by Codex on 2026/2/12.
//

import Foundation
import SwiftData

/// 合并跨设备产生的同名标签，并维护规范化名称。
///
/// 每台设备都会独立执行合并并把结果同步出去，因此"保留哪一个"必须在所有设备上一致，
/// 否则两台设备会各删一个，最终同名标签全部消失。
/// 使用次数是派生数据，不在这里写库（见 `Tag.activeMemoCount`）。
enum TagMaintenance {
    nonisolated static func reconcile(tags: [Tag], in context: ModelContext) -> Bool {
        var hasChanges = false
        var tagsByNormalizedName: [String: [Tag]] = [:]

        for tag in tags {
            let normalized = Tag.normalizedKey(for: tag.name)
            if tag.normalizedName != normalized {
                tag.normalizedName = normalized
                hasChanges = true
            }
            if !normalized.isEmpty {
                tagsByNormalizedName[normalized, default: []].append(tag)
            }
        }

        for duplicates in tagsByNormalizedName.values where duplicates.count > 1 {
            guard let canonical = canonicalTag(in: duplicates) else {
                // 无法在所有设备上得出一致结论时宁可暂留重复标签，也不冒险两边各删一个。
                continue
            }

            for duplicate in duplicates where duplicate !== canonical {
                merge(duplicate, into: canonical)
                context.delete(duplicate)
                hasChanges = true
            }
        }

        return hasChanges
    }

    /// 创建时间相差小于此值时视为"无法判定先后"。
    /// CloudKit 只保存毫秒精度，创建设备本地却是完整精度，且舍入方式未知，
    /// 同一个标签在不同设备上的 `createdAt` 会有约 1ms 的偏差。
    nonisolated static let createdAtTolerance: TimeInterval = 1

    /// 选出要保留的标签；无法确定时返回 nil（本轮不合并）。
    ///
    /// 只有当某个标签比其余所有标签都早至少 `createdAtTolerance` 时才合并。
    /// 这样任何"做出决定"的设备都会选中同一个标签（偏差远小于容差）；
    /// 处在阈值边界时某台设备可能跳过、另一台合并，但跳过不删除任何东西，结果依然一致。
    /// 不能用 `persistentModelID` 或名称兜底：前者各设备不同，
    /// 后者会让"按时间判定"与"按名称判定"的设备删掉不同的标签。
    nonisolated static func canonicalTag(in duplicates: [Tag]) -> Tag? {
        let ordered = duplicates.sorted { $0.createdAt < $1.createdAt }
        guard let earliest = ordered.first else { return nil }
        guard ordered.count > 1 else { return earliest }
        let gap = ordered[1].createdAt.timeIntervalSince(earliest.createdAt)
        return gap >= createdAtTolerance ? earliest : nil
    }

    private nonisolated static func merge(_ duplicate: Tag, into canonical: Tag) {
        let duplicateID = duplicate.persistentModelID
        let canonicalID = canonical.persistentModelID
        let affectedMemos = duplicate.memosList

        for memo in affectedMemos {
            var tags = memo.tagsList.filter {
                $0.persistentModelID != duplicateID
                    && $0.persistentModelID != canonicalID
            }
            tags.append(canonical)
            memo.tags = tags
        }
    }
}
