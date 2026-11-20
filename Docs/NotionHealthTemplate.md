# Hadge Health Notion Template

Template page: <https://app.notion.com/p/Hadge-41e86019c92c81e8bf9dcbc142ba8003>

The template lives under the `Keep` page and contains two databases. The iOS
app discovers them from the template page, so users can duplicate the page and
use the copy without changing code.

## Daily health

One row represents one calendar day. The `同步 ID` value is
`daily-YYYY-MM-DD`.

| Property | Type | Meaning |
| --- | --- | --- |
| 名称 | Title | Date-based row name |
| 同步 ID | Text | Stable upsert key |
| 日期 | Date | Day represented by the row |
| 步数 | Number | Daily step count |
| 饮水（毫升） | Number | Daily water intake |
| 睡眠（分钟） | Number | Merged asleep duration |
| 活动能量（千卡） | Number | Apple Activity move value |
| 锻炼（分钟） | Number | Apple Activity exercise value |
| 站立（小时） | Number | Apple Activity stand value |
| 活动能量目标 | Number | Activity move goal |
| 锻炼目标 | Number | Activity exercise goal |
| 站立目标 | Number | Activity stand goal |
| 来源 | Select | Data source |
| 最近同步 | Date | Last update from Hadge |

Views: `最近健康`, `健康日历`, and `步数趋势`.

## Workout records

One row represents one HealthKit workout. The `同步 ID` value is derived from
the workout UUID.

| Property | Type | Meaning |
| --- | --- | --- |
| 名称 | Title | Time and activity category |
| 同步 ID | Text | Stable upsert key |
| 开始时间 | Date | Workout start |
| 结束时间 | Date | Workout end |
| 运动类型 | Select | Running, walking, cycling, etc. |
| 时长（分钟） | Number | Duration |
| 距离（公里） | Number | Total distance |
| 活动能量（千卡） | Number | Active energy |
| 最小心率 | Number | Minimum heart rate |
| 平均心率 | Number | Average heart rate |
| 最大心率 | Number | Maximum heart rate |
| 轨迹点数 | Number | Count of available route points |
| 包含轨迹 | Checkbox | Whether a route was found |
| 来源 | Select | Data source |
| 最近同步 | Date | Last update from Hadge |

Views: `最近运动`, `按运动类型`, and `运动日历`.

## Sync behavior

1. Duplicate the template page.
2. Connect the copied page to the Hadge Notion integration.
3. In Hadge, open `设置 → 数据导出 → Notion`.
4. Paste the integration token and copied page URL.
5. Choose the first import range and start syncing.

The integration token is stored in the iOS Keychain. It is never written to
this repository or included in exported JSON/CSV files. After the first sync,
Hadge queries existing `同步 ID` values and updates the last seven days,
creating rows that do not exist yet.
