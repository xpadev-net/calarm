いい。前提をこう置くと、実装計画はかなり具体化できます。

* **UI・状態管理・データ管理はFlutterで共通化**
* **アラームの予約・発火・ロック画面表示だけSwift/Kotlinのネイティブ層**
* **iOSは26以上前提なのでAlarmKitを使う**
* **AndroidはAndroid 16、つまりAPI 36前提として組む**
* **外部カレンダー連携はまだ入れない。週カレンダー風UIはあくまでWake Planを作るためのローカルUI**

FlutterからSwift/KotlinのOS固有APIを呼ぶ構成は、Flutter公式のPlatform Channelの用途そのものです。設定UIや週カレンダーはFlutter、アラーム予約はネイティブに逃がす、という分け方で進めるのがよさそうです。([Flutterドキュメント][1])

---

# 実装方針

## 全体アーキテクチャ

```text
Flutter
├─ 週カレンダーUI
├─ WakePlan作成・編集UI
├─ WakePlan / Occurrence生成ロジック
├─ ローカルDB
├─ 設定画面
└─ NativeAlarmGateway
   ├─ iOS Swift: AlarmKit
   └─ Android Kotlin: AlarmManager + Full-screen notification
```

重要なのは、**Flutterは「いつ鳴らすべきか」を計算する層**、**ネイティブは「OSに確実に鳴らしてもらう層」**にすることです。Flutter側だけでタイマー的に実装すると、アプリ終了時・ロック中・省電力中に破綻しやすいので、そこは最初からやらないほうがいいです。

iOS 26以上前提なら、AlarmKitを使う前提でよいです。AlarmKitはiOS/iPadOS 26でアプリ独自のアラーム/タイマーをLock ScreenやDynamic Islandなどに出せる仕組みで、固定時刻や曜日繰り返しのスケジュール、カスタム音、アラームライフサイクル管理を扱えます。ユーザー許可と `NSAlarmKitUsageDescription` は必要です。([Apple Developer][2])

Android 16前提なら、Android側は `compileSdk = 36` / `targetSdk = 36` で組みます。Android公式ドキュメントでもAndroid 16 APIを使って挙動変更をテストするにはAndroid 16 SDKをセットアップし、`compileSdk` と `targetSdk` を36にする流れが示されています。([Android Developers][3])

---

# MVPの画面構成

## 1. 週カレンダー画面

これをホーム画面にします。

見た目は添付のような週カレンダーで、横が日付、縦が時間です。ただし、外部カレンダー予定を出すのではなく、最初は **Wake Planだけを表示する専用カレンダー** と考えるのがよいです。

```text
画面:
- 日付ヘッダー
- 縦軸: 時間
- 横軸: 日
- Wake Planブロック
- 現在時刻ライン
- タップで作成
- 既存ブロックタップで詳細・編集
```

表示例はこうです。

```text
07:00 起床
06:00〜07:00 / 5分おき / 13回
```

Wake Planは普通の予定ブロックとは少し意味が違います。予定なら「その時間帯に何かがある」ですが、このアプリでは **「この時間帯に段階的に起こす」** という意味です。なので、ブロックは `startAt = targetAt - window` から `targetAt` まで表示し、ブロック下端を起床目標時刻として強調すると分かりやすいです。

---

## 2. タップで作成するUI

任意の箇所をタップすると、その日その時間を **起床目標時刻** として作成メニューを出します。

```text
例:
火曜 07:00 をタップ
→ 「7/7(火) 07:00に起きる」作成シートを表示
```

作成シートのMVP項目はこれで十分です。

```text
- 起床目標時刻
- この日だけ / 繰り返し
- 何分前から鳴らすか
- 何分おきに鳴らすか
- アラーム音
- バイブ
- プレビュー
```

初期値はこれ。

```text
起床ウィンドウ: 60分前
間隔: 5分
繰り返し: なし
音: デフォルト
バイブ: ON
```

作成前に必ずプレビューを出します。

```text
06:00〜07:00に5分おき
合計13回鳴ります
```

ここでユーザーが「作成」を押したらWake Planを保存し、生成されたAlarm Occurrenceをネイティブ層へ予約します。

---

## 3. アラーム鳴動画面

ここはシンプルでよいです。

```text
表示:
- 現在の時刻
- 起床目標時刻
- 何回目のアラームか
- 次に鳴る時刻

操作:
- 今のアラームを止める
```

表示しないもの。

```text
- 起きた
- 残り全部停止
- チャレンジ
- 問題
- ミッション
- スヌーズ
```

iOSではAlarmKitのシステムUIを使うのが自然です。AlarmKitのアラートは停止ボタン、任意のスヌーズボタン、カスタムボタンを構成できますが、このアプリではスヌーズを出さず、現在のアラームを止めるだけに寄せます。Appleの説明ではAlarmKitのアラートはサイレントモードやFocusを突破し、ユーザーがアプリごとに許可する設計です。([Apple Developer][2])

Androidでは、ロック中に普通のアラームのように画面を出すためにfull-screen intentを使う構成が合います。Android公式ドキュメントでも、着信や鳴動中アラームのような緊急・時間依存の用途ではfull-screen intentを通知に関連付けられると説明されています。([Android Developers][4])

---

# 週カレンダーUIの実装計画

## 実装は自前がよい

既存のカレンダーライブラリを使うより、MVPでは自前実装がよいです。

理由は、このUIが「予定表示カレンダー」ではなく、**Wake Planを作るための時間グリッド**だからです。タップ位置から日時を正確に逆算する、Wake Planブロックを目標時刻から逆算して描く、将来的に外部カレンダー予定も重ねる、という要件があるので、`PageView` + `CustomPainter` + `Stack` で作るほうが制御しやすいです。

構成イメージ。

```text
WeekCalendarScreen
├─ WeekHeader
│  └─ 日付・曜日
├─ TimeGridBody
│  ├─ TimeAxis
│  ├─ WeekPageView
│  │  └─ WeekGridPage
│  │     ├─ GridPainter
│  │     ├─ WakePlanBlockLayer
│  │     ├─ CurrentTimeLine
│  │     └─ TapGestureLayer
└─ CreateWakePlanSheet
```

## 横方向の無限スクロール

実装は `PageView.builder` でよいです。

```text
baseWeekStart = 今週の日曜 00:00
initialPage = 10000

pageIndex 10000 = 今週
pageIndex 10001 = 来週
pageIndex 9999 = 先週
```

日付計算はこうします。

```text
weekStart = baseWeekStart + Duration(days: (pageIndex - initialPage) * 7)
```

完全な意味での無限ではないですが、実用上は十分です。

## 縦方向の時間軸

内部モデルは **00:00〜24:00** で持つべきです。

添付画像のように表示上は 07:00〜23:00 が見えていても、アラームアプリでは早朝や深夜が重要です。特に、起床目標が00:30で60分前から鳴らす場合、前日23:30から始まるので、内部的には日跨ぎを扱える必要があります。

初期スクロール位置は、朝向けならこのあたりがよいです。

```text
初期表示:
- 今日なら現在時刻付近
- それ以外なら 05:00 付近
```

## タップ位置から日時への変換

考え方はシンプルです。

```text
dayIndex = tapX / dayColumnWidth
minutesFromDayStart = tapY / pxPerMinute
snappedMinutes = 5分単位に丸める
targetDate = weekStart + dayIndex日
targetAt = targetDate + snappedMinutes
```

MVPでは5分刻みに丸めるのがよいです。1分単位にするとUIが細かすぎるし、今回のコンセプトとも少しズレます。

## Wake Planブロックの描画

Wake Planは、目標時刻から逆算してブロック表示します。

```text
targetAt = 07:00
startOffset = 60分
interval = 5分

blockStart = 06:00
blockEnd = 07:00
```

ブロック内には以下を表示します。

```text
07:00 起床
06:00〜07:00
5分おき / 13回
```

細かいアラーム時刻を全部テキスト表示すると見づらいので、ブロックの端に小さい点やメモリを置くくらいでよいです。MVPではテキストだけでも十分です。

---

# アラーム生成ロジック

## 基本ルール

```text
startAt = targetAt - startOffsetMinutes
endAt = targetAt
interval = intervalMinutes
```

生成ルールは、**開始時刻と起床目標時刻を必ず含める** でよいです。

```text
targetAt: 07:00
startOffset: 60分
interval: 5分

occurrences:
06:00
06:05
06:10
...
06:55
07:00
```

この場合は13回です。

## startOffsetがintervalで割り切れない場合

ここは仕様を決めておいたほうがいいです。

おすすめはこれです。

```text
1. startAtは必ず含める
2. startAtからintervalごとに追加
3. targetAtを超える直前まで追加
4. 最後にtargetAtを必ず追加
```

例:

```text
targetAt: 07:00
startOffset: 45分
interval: 10分

startAt: 06:15

occurrences:
06:15
06:25
06:35
06:45
06:55
07:00
```

最後だけ5分間隔になりますが、「45分前から鳴らす」と「07:00にも必ず鳴らす」の両方を満たせます。プレビューで分かるので問題になりにくいです。

## 同日・すでにウィンドウ内の場合

たとえば現在時刻が06:20で、07:00起床、60分前から5分おきのプランを作る場合、06:00〜06:20の過去分は予約しません。

```text
今: 06:20
targetAt: 07:00

本来:
06:00, 06:05, 06:10, 06:15, 06:20, 06:25...

実際に予約:
06:25, 06:30, ..., 07:00
```

プレビューではこう表示すると親切です。

```text
本来: 13回
今回残り: 8回
```

---

# データモデル

Flutter側のメインモデルはこれでよいです。

```text
WakePlan
- id
- title
- scheduleType
  - oneShot
  - weekly
- oneShotDate
- repeatDays
- targetTimeMinutes
- startOffsetMinutes
- intervalMinutes
- soundId
- vibrationEnabled
- enabled
- skipNextDate
- createdAt
- updatedAt
```

`targetTimeMinutes` は、00:00からの分です。

```text
07:00 = 420
22:30 = 1350
```

一回限りの場合は `oneShotDate + targetTimeMinutes` で日時を作ります。
繰り返しの場合は `repeatDays + targetTimeMinutes` で次回インスタンスを生成します。

個々のアラームはこうです。

```text
AlarmOccurrence
- id
- wakePlanId
- scheduledAt
- targetAt
- indexInPlan
- totalInPlan
- status
- platformAlarmId
- createdAt
- updatedAt
```

状態はこのくらい。

```text
scheduled
ringing
dismissed
expired
cancelled
failed
```

重要なのは、**Occurrenceを止めてもWakePlanは止まらない** ことです。

```text
06:00 occurrence dismissed
→ WakePlanはactiveのまま
→ 06:05 occurrenceはscheduledのまま
```

---

# Flutter側の主要コンポーネント

## 1. OccurrencePlanner

Wake Planから実際のアラーム時刻を作る純粋ロジックです。

```text
WakePlan
+ visibleRange
+ now
→ WakeInstance[]
→ AlarmOccurrence[]
```

これは必ずユニットテストを書きます。

テストケース。

```text
- 07:00 / 60分 / 5分 → 13回
- 07:00 / 45分 / 10分 → 06:15, 06:25, ..., 07:00
- targetAtが過去なら作成不可
- window途中で作成したら未来分だけ予約
- 日跨ぎ
- 平日繰り返し
- 次回だけスキップ
```

## 2. WakePlanRepository

Wake Planを保存・取得する層です。

```text
savePlan()
updatePlan()
deletePlan()
findPlansInRange()
findEnabledPlans()
```

外部カレンダー連携を将来入れるなら、ここはWake Plan専用のRepositoryにしておき、カレンダー予定は別のRepositoryにします。混ぜないほうが後で楽です。

## 3. NativeAlarmGateway

Flutterからネイティブへ渡す抽象層です。

```dart
abstract class NativeAlarmGateway {
  Future<AlarmCapability> getCapability();
  Future<void> requestPermissionIfNeeded();
  Future<ScheduleResult> scheduleOccurrences(List<AlarmOccurrenceDraft> occurrences);
  Future<void> cancelOccurrences(List<String> platformAlarmIds);
  Future<void> cancelPlan(String wakePlanId);
  Future<void> scheduleTestAlarm(Duration delay);
}
```

MethodChannel名はこんな感じ。

```text
com.example.wake_alarm/native_alarm
```

最初はMethodChannelで十分です。型安全にしたくなったらPigeon化、という順番でよいです。

---

# iOS実装計画

## 方針

iOSは26以上前提なので、AlarmKitのみを使います。ローカル通知フォールバックは不要です。

iOS側はSwiftで `AlarmKitBridge` を作り、Flutterから以下を呼びます。

```text
- authorizationState
- requestAuthorization
- scheduleAlarm
- cancelAlarm
- cancelPlan
- scheduleTestAlarm
```

AlarmKitでは、アラームを作るためにスケジュール、表示属性、サウンド、ライフサイクル管理を扱います。AppleのWWDC説明では、固定スケジュールと相対スケジュールがあり、相対スケジュールでは時刻と任意の曜日繰り返しを指定できるとされています。([Apple Developer][2])

## iOSの予約方式

このアプリでは、**1つのWake Planを複数のAlarmKit alarmに展開**します。

```text
WakePlan: 07:00 / 60分前 / 5分おき

AlarmKit alarms:
06:00
06:05
06:10
...
07:00
```

それぞれのアラームに一意なIDを付けます。

```text
wakePlanId + occurrence timestamp
```

例:

```text
plan_abc_20260707_0600
plan_abc_20260707_0605
...
```

繰り返しWake Planの場合、iOS側でAlarmKitのrelative schedule + weekly recurrenceを使えるかを最初に検証します。ここは最初の技術スパイクで確認すべきポイントです。AlarmKitの仕様上、特定日のみスキップをきれいに扱えない場合は、繰り返しを「固定Occurrenceのローリング予約」で実装するか、次回スキップだけ実装を後ろに回す判断が必要です。

## iOSスパイクで確認すること

最初にこれだけは確認したほうがいいです。

```text
1. 5分おきに13個のAlarmKitアラームを予約できるか
2. それらがロック中に順番に鳴るか
3. サイレント/Focus中の挙動
4. 停止ボタンでその1回だけ止まるか
5. 未来のAlarmKitアラームがキャンセルされないか
6. 編集時に古いAlarmKitアラームを確実にcancelできるか
7. weekday recurrenceを13本張れるか
8. AlarmKitの実用上限に当たらないか
```

このスパイクが通れば、iOSはかなり見通しがよくなります。

---

# Android実装計画

## 方針

AndroidはKotlinで `AlarmBridge` を作ります。

構成はこうです。

```text
AlarmBridge.kt
AlarmReceiver.kt
AlarmRingingActivity.kt
BootReceiver.kt
```

AndroidのAlarmManagerは、アプリが動いていないときや端末がスリープ中でも時刻ベースの処理を発火できる仕組みです。公式ドキュメントでも、AlarmManagerのアラームはアプリのライフタイム外で動作し、アプリが実行中でなくても、端末がスリープ中でもトリガーできると説明されています。([Android Developers][5])

## Androidの予約方式

Androidでは、アラーム時計用途に近いので、まず `setAlarmClock()` を第一候補にします。公式ドキュメントでは、`setAlarmClock()` は正確な時刻に発火し、ユーザーに高く可視化され、低電力モードから抜けて配信される最も重要なアラームとして扱われると説明されています。([Android Developers][5])

ただし、5分おきに複数回鳴らす設計はバッテリーやシステムリソースへの影響があるため、上限は設けます。Android公式もExact Alarmはリソース消費が大きく、可能ならinexact alarmを推奨すると説明していますが、このアプリは「指定時刻に起こす」こと自体がコアなのでExact Alarmを使う理由は立ちます。([Android Developers][5])

Android 13以降では `SCHEDULE_EXACT_ALARM` と `USE_EXACT_ALARM` の選択があります。`USE_EXACT_ALARM` は自動付与・ユーザーが取り消せない一方で用途が限定され、`SCHEDULE_EXACT_ALARM` はユーザー付与でより広い用途に使える、という違いがあります。公開配布するなら、アラーム時計アプリとして `USE_EXACT_ALARM` の対象にできるかを確認し、手元検証や内部配布ならまず `SCHEDULE_EXACT_ALARM` で動作確認するのが現実的です。([Android Developers][5])

## Androidの鳴動画面

AlarmReceiverが発火したら、full-screen notification経由で `AlarmRingingActivity` を出します。

```text
AlarmReceiver
→ full-screen notification
→ AlarmRingingActivity
→ FlutterのAlarmRingingPage または native最小画面
```

ユーザーがロック中ならフルスクリーンのActivityが出て、ロック解除中なら展開通知になる、という挙動がAndroid公式に説明されています。([Android Developers][4])

Flutterで共通化したい場合、Androidの `AlarmRingingActivity` はFlutter画面を起動してもよいです。ただし、アプリが完全終了している状態だとFlutterエンジン起動に時間がかかる可能性があるので、MVPの安全策としては **nativeの最小アラーム画面をフォールバックとして持つ** のがよいです。

```text
理想:
AndroidもFlutterのAlarmRingingPage

安全策:
Flutter起動が遅い/失敗したらKotlinの最小画面で
「今のアラームを止める」だけ出す
```

## Androidの再起動対応

Androidでは端末再起動時にアラームが消えるので、BootReceiverで再予約が必要です。公式ドキュメントでも、端末シャットダウンでアラームはキャンセルされるため、再起動後に自動的に再起動する設計が必要とされています。([Android Developers][5])

さらに、再起動後まだユーザーがロック解除していない状態でもアラームを扱いたい場合はDirect Boot対応も検討します。Android公式ドキュメントでは、アラーム時計アプリのようなスケジュール通知はDirect Boot対応の代表例として挙げられています。([Android Developers][6])

MVPでは最低限これ。

```text
- BOOT_COMPLETEDを受けて再スケジュール
- Flutter DBだけに依存せず、native側にも最低限のWakePlan情報をミラー保存
```

---

# 実装フェーズ

## P0: ネイティブアラーム技術スパイク

最初にやるべきです。カレンダーUIより先です。

目的は、**5分おき複数アラームがOS上で本当に成立するか確認すること**。

### iOSスパイク

```text
- AlarmKit認可
- 1分後のテストアラーム
- 5分間隔で3個
- 5分間隔で13個
- アプリ終了中
- ロック中
- サイレント/Focus中
- 停止しても次が鳴るか
- 全cancelできるか
```

### Androidスパイク

```text
- exact alarm権限確認
- 1分後のテストアラーム
- setAlarmClockで単発
- 5分間隔で3個
- 5分間隔で13個
- ロック中のfull-screen表示
- アプリ終了中
- 端末再起動後の再予約
- 通知権限拒否時の挙動
```

Android 13以降は通知のruntime permissionである `POST_NOTIFICATIONS` も考慮が必要です。Android公式ドキュメントでは、Android 13/API 33以降でアプリが通知を送るには `POST_NOTIFICATIONS` runtime permissionが導入されていると説明されています。([Android Developers][7])

このP0で詰まるなら、UIに時間を使う前に設計を変えたほうがいいです。

---

## P1: Flutterのドメイン実装

ここではネイティブをまだ本接続せず、Fake Schedulerで進めます。

作るもの。

```text
- WakePlan model
- AlarmOccurrence model
- OccurrencePlanner
- WakePlanRepository
- AppSettings
- FakeNativeAlarmGateway
```

この段階で、次のユニットテストを通します。

```text
07:00 / 60分 / 5分 → 13回
07:00 / 30分 / 10分 → 4回
07:00 / 45分 / 10分 → 06:15, 06:25, 06:35, 06:45, 06:55, 07:00
作成時点で過去のOccurrenceは除外
日跨ぎ
曜日繰り返し
次回だけスキップ
編集時にOccurrence再生成
```

---

## P2: 週カレンダーUI

作る順番はこれがよいです。

```text
1. 日付ヘッダー
2. 縦時間グリッド
3. 横PageViewによる週移動
4. 現在時刻ライン
5. タップ位置から日時変換
6. WakePlanブロック描画
7. 既存ブロックタップ
8. 作成BottomSheet
9. 詳細BottomSheet
```

MVPではドラッグ編集はいらないです。

```text
MVP:
- タップで作成
- ブロックタップで編集

将来:
- ブロックドラッグで時刻変更
- 長押し複製
- ピンチで時間軸ズーム
```

---

## P3: 作成・編集フロー

作成フロー。

```text
週カレンダーで07:00をタップ
→ 作成BottomSheet
→ デフォルト 60分前 / 5分おき
→ プレビュー
→ 作成
→ WakePlan保存
→ Occurrence生成
→ NativeAlarmGateway.schedule
→ カレンダーにブロック表示
```

編集フロー。

```text
WakePlanブロックをタップ
→ 詳細BottomSheet
→ 編集
→ 保存
→ 既存Occurrence cancel
→ 新Occurrence生成
→ NativeAlarmGateway.schedule
```

削除フロー。

```text
WakePlanブロックをタップ
→ 詳細
→ 削除
→ NativeAlarmGateway.cancelPlan
→ DBから無効化/削除
```

MVPでは物理削除より、内部的には `deleted` / `disabled` にしておくほうがデバッグしやすいです。

---

## P4: ネイティブ接続

P0で通したネイティブ実装を、Flutterの `NativeAlarmGateway` に接続します。

保存時の流れ。

```text
WakePlan保存
→ Occurrence生成
→ DB保存
→ native schedule
→ schedule結果をDBに反映
```

失敗時。

```text
- DBにはWakePlanを残す
- status = scheduleFailed
- ホーム画面に警告
- 権限チェック導線を表示
```

編集時は必ずこの順番です。

```text
1. 古いplatformAlarmIdをcancel
2. 新しいOccurrenceを生成
3. 新しいplatformAlarmIdでschedule
4. DB更新
```

古いアラームが残ると信用を失うので、ここはかなり重要です。

---

## P5: 繰り返し・次回スキップ

繰り返しはMVPに入れたいですが、実装順としては一回限りの後でよいです。

対応する繰り返し。

```text
- 毎日
- 平日
- 土日
- 任意曜日
```

次回スキップ。

```text
平日07:00 WakePlan
→ 明日の分だけskip
→ 明後日以降は通常通り
```

注意点として、iOSのAlarmKit relative recurrenceで「特定日だけ除外」がきれいにできるかは要検証です。ここが難しければ、MVPの内部実装としては「次回分の具体Occurrenceだけcancelし、次々回以降は再予約」という形に寄せます。

---

## P6: 設定・ヘルスチェック

設定画面。

```text
- デフォルト起床ウィンドウ
- デフォルト間隔
- デフォルト音
- バイブ
- テストアラーム
- 権限チェック
```

ヘルスチェック。

```text
iOS:
- AlarmKit authorization
- 音設定
- テストアラーム

Android:
- exact alarm権限
- notification権限
- full-screen intent可否
- 通知チャンネル
- バッテリー/省電力注意
- BootReceiver状態
```

---

# ディレクトリ構成案

最初はこうで十分です。

```text
lib/
  main.dart
  app.dart

  core/
    time/
      local_time.dart
      date_range.dart
      occurrence_math.dart
    platform/
      native_alarm_gateway.dart

  features/
    week_calendar/
      week_calendar_screen.dart
      week_header.dart
      time_grid.dart
      wake_plan_block.dart
      current_time_line.dart

    wake_plan/
      domain/
        wake_plan.dart
        alarm_occurrence.dart
        repeat_rule.dart
      application/
        occurrence_planner.dart
        wake_plan_service.dart
      data/
        wake_plan_repository.dart
      ui/
        create_wake_plan_sheet.dart
        wake_plan_detail_sheet.dart

    alarm_ringing/
      alarm_ringing_page.dart

    settings/
      settings_screen.dart
      alarm_health_check_screen.dart

ios/
  Runner/
    AlarmKitBridge.swift

android/
  app/src/main/kotlin/.../
    alarm/
      AlarmBridge.kt
      AlarmReceiver.kt
      AlarmRingingActivity.kt
      BootReceiver.kt
```

将来、ネイティブ層が大きくなったらFlutter pluginとして切り出せばいいです。最初からpackage分割しすぎると遅くなります。

---

# 最初の縦切り実装

最初の完成目標はこれです。

```text
1. 週カレンダーで今日07:00をタップ
2. 作成シートが出る
3. 60分前/5分おきのプレビューが出る
4. 作成できる
5. カレンダーに06:00〜07:00のWakePlanブロックが出る
6. ネイティブに1〜3個だけテスト予約する
7. ロック中に鳴る
8. 「今のアラームを止める」で止まる
9. 次のアラームはキャンセルされず鳴る
```

最初から13個・繰り返し・スキップまで全部やらず、まずは3個で成立確認するのがいいです。

```text
テスト用:
今から1分後
今から2分後
今から3分後
```

これが通ったら、本来の5分間隔・13個に戻します。

---

# 実装上の注意点

## 1. カレンダーUIと外部カレンダー連携を混同しない

今回作るのは **カレンダー風のWake Planエディタ** です。
Google Calendar / Apple Calendarの予定表示ではありません。

将来、外部カレンダーを重ねるならこうします。

```text
WeekGrid
├─ ExternalCalendarEventLayer
└─ WakePlanLayer
```

今は `WakePlanLayer` だけでよいです。

## 2. 鳴動画面は共通化しすぎない

設定UIはFlutter共通化でよいです。
ただし、アラーム発火時だけはOSに寄せたほうが安全です。

```text
iOS:
AlarmKitのシステムアラート

Android:
full-screen intentでFlutter画面
ただしnative fallbackを持つ
```

「全部Flutterで鳴らす」は避けたほうがいいです。

## 3. 未来分を無限生成しない

繰り返しWake Planで未来数年分のOccurrenceをDBに作るのは避けます。

```text
Flutter表示:
表示中の週だけ動的生成

ネイティブ予約:
直近必要分だけ予約
```

Androidは再起動やExact Alarm権限変更で再予約が必要なので、native側にも最低限のWakePlan情報をミラーしておくのがよいです。

## 4. 重複アラームをどうするか

同じ時刻に複数Wake Planが重なる可能性があります。

MVPでは禁止せず、警告でよいです。

```text
この時間帯には別の起床プランがあります
それでも作成しますか？
```

完全禁止にすると、ユーザーが意図して強めたいケースを潰します。

## 5. 鳴動中に「残り停止」を出さない

これは前の方針通りです。

ただし、アプリの詳細画面から削除・無効化はできるようにしておきます。

```text
鳴動中:
今のアラームを止めるだけ

詳細画面:
削除
無効化
次回だけスキップ
```

---

# MVPリリース基準

MVPとしては、以下が通ればよいです。

```text
- 週カレンダーUIでWake Planを作成できる
- Wake Planブロックが正しく表示される
- 60分前/5分おきでOccurrenceが生成される
- 一回限りWake Planが鳴る
- 1回止めても次が鳴る
- 曜日繰り返しが鳴る
- 次回だけスキップできる
- 編集時に古いアラームが残らない
- 削除時に未来アラームがcancelされる
- テストアラームがある
- 権限不足時に警告が出る
```

---

# 開発順序まとめ

```text
P0 ネイティブアラームスパイク
??? from here until ???END lines may have been inserted/deleted
P1 WakePlan / Occurrenceの純粋ロジック
P2 週カレンダーUI
P3 作成・編集・削除フロー
P4 iOS AlarmKit接続
P5 Android AlarmManager接続
P6 繰り返し・次回スキップ
P7 設定・テストアラーム・権限チェック
P8 実機QA
```

この順番がいいです。

特に、**P0のネイティブアラームスパイクを最初にやる**のが重要です。週カレンダーUIはFlutterで作り切れる見込みが高いですが、5分おき複数アラームがiOS/Androidの実機で期待通り動くかは、実装前提を左右します。

このプロダクトの最小縦切りは、

```text
週カレンダーで07:00をタップ
→ 06:00〜07:00のWake Planができる
→ 1回止めても次が鳴る
```

です。まずここだけを通すのが一番早いです。

[1]: https://docs.flutter.dev/platform-integration/platform-channels "Writing custom platform-specific code"
[2]: https://developer.apple.com/videos/play/wwdc2025/230/ "Wake up to the AlarmKit API - WWDC25 - Videos - Apple Developer"
[3]: https://developer.android.com/about/versions/16/setup-sdk "Set up the Android 16 SDK  |  Android Developers"
[4]: https://developer.android.com/develop/ui/compose/notifications/create-notification "Create a notification  |  Jetpack Compose  |  Android Developers"
[5]: https://developer.android.com/develop/background-work/services/alarms "Schedule alarms  |  Background work  |  Android Developers"
[6]: https://developer.android.com/privacy-and-security/direct-boot "Support Direct Boot mode  |  Security  |  Android Developers"
[7]: https://developer.android.com/develop/ui/compose/notifications/notification-permission?
???END
