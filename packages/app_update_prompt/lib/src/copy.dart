/// Built-in copy for the prompt: en, vi, zh, ko, ja. Short on purpose
/// (banner <= 12 words, parent-facing in Kids apps).
library;

class UpdateCopy {
  const UpdateCopy({
    required this.title,
    required this.update,
    required this.later,
    required this.dismissLabel,
    required this.downloadedTitle,
    required this.restart,
    required this.requiredTitle,
    required this.requiredBody,
    required this.requiredBodyForParents,
  });

  final String title;
  final String update;
  final String later;
  final String dismissLabel;
  final String downloadedTitle;
  final String restart;
  final String requiredTitle;
  final String requiredBody;

  /// Used by Kids apps: the screen may be seen by a child.
  final String requiredBodyForParents;

  static const List<String> languages = ['en', 'vi', 'zh', 'ko', 'ja'];

  static UpdateCopy forLanguage(String code) => _copy[code] ?? _copy['en']!;

  static const Map<String, UpdateCopy> _copy = {
    'en': UpdateCopy(
      title: 'A new version is ready',
      update: 'Update',
      later: 'Later',
      dismissLabel: 'Dismiss update notice',
      downloadedTitle: 'Update downloaded',
      restart: 'Restart',
      requiredTitle: 'Please update',
      requiredBody: 'This version has a problem. Update to keep using the app.',
      requiredBodyForParents: 'Please ask a grown-up to update the app.',
    ),
    'vi': UpdateCopy(
      title: 'Đã có phiên bản mới',
      update: 'Cập nhật',
      later: 'Để sau',
      dismissLabel: 'Đóng thông báo cập nhật',
      downloadedTitle: 'Đã tải xong bản cập nhật',
      restart: 'Khởi động lại',
      requiredTitle: 'Vui lòng cập nhật',
      requiredBody:
          'Phiên bản này đang gặp lỗi. Hãy cập nhật để tiếp tục dùng ứng dụng.',
      requiredBodyForParents: 'Nhờ người lớn cập nhật ứng dụng nhé.',
    ),
    'zh': UpdateCopy(
      title: '新版本已就绪',
      update: '更新',
      later: '稍后',
      dismissLabel: '关闭更新提示',
      downloadedTitle: '更新已下载',
      restart: '重启',
      requiredTitle: '请更新',
      requiredBody: '此版本存在问题。请更新后继续使用。',
      requiredBodyForParents: '请让家长更新应用。',
    ),
    'ko': UpdateCopy(
      title: '새 버전이 준비되었어요',
      update: '업데이트',
      later: '나중에',
      dismissLabel: '업데이트 알림 닫기',
      downloadedTitle: '업데이트를 내려받았어요',
      restart: '다시 시작',
      requiredTitle: '업데이트해 주세요',
      requiredBody: '이 버전에 문제가 있어요. 업데이트 후 계속 사용해 주세요.',
      requiredBodyForParents: '보호자께서 앱을 업데이트해 주세요.',
    ),
    'ja': UpdateCopy(
      title: '新しいバージョンがあります',
      update: 'アップデート',
      later: 'あとで',
      dismissLabel: 'アップデートのお知らせを閉じる',
      downloadedTitle: 'アップデートをダウンロードしました',
      restart: '再起動',
      requiredTitle: 'アップデートしてください',
      requiredBody: 'このバージョンには問題があります。アップデートしてお使いください。',
      requiredBodyForParents: '保護者の方がアプリをアップデートしてください。',
    ),
  };
}
