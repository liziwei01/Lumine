using System;
using System.Globalization;

namespace Lumine.Windows;

public static class L10n
{
    public static readonly string[] Codes = ["en", "zh", "ru", "ja", "ko"];
    public static readonly string[] Names = ["English", "简体中文", "Русский", "日本語", "한국어"];
    public static string Language { get; set; } = "en";
    public static string SystemLanguage => Array.IndexOf(Codes, CultureInfo.CurrentUICulture.TwoLetterISOLanguageName) >= 0
        ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName : "en";
    public static string T(string key)
    {
        var index = Math.Max(0, Array.IndexOf(Codes, Language));
        return key switch
        {
            "subtitle" => new[] { "Your system, at a glance", "系统状态，一目了然", "Система как на ладони", "システムの状態をひと目で", "시스템 상태를 한눈에" }[index],
            "cpu" => new[] { "CPU", "处理器", "Процессор", "CPU", "CPU" }[index],
            "memory" => new[] { "Memory", "内存", "Память", "メモリ", "메모리" }[index],
            "disk" => new[] { "Storage", "磁盘", "Диски", "ストレージ", "저장 공간" }[index],
            "battery" => new[] { "Battery", "电池", "Батарея", "バッテリー", "배터리" }[index],
            "network" => new[] { "Network", "网络", "Сеть", "ネットワーク", "네트워크" }[index],
            "devices" => new[] { "Removable storage", "可移动存储", "Съёмные диски", "リムーバブルディスク", "이동식 저장 장치" }[index],
            "settings" => new[] { "Settings", "设置", "Настройки", "設定", "설정" }[index],
            "open" => new[] { "Open Lumine", "打开 Lumine", "Открыть Lumine", "Lumine を開く", "Lumine 열기" }[index],
            "quit" => new[] { "Quit", "退出", "Выход", "終了", "종료" }[index],
            "hide" => new[] { "Hide to tray", "收起到托盘", "Свернуть в трей", "トレイに格納", "트레이로 숨기기" }[index],
            "unavailable" => new[] { "Unavailable", "不可用", "Недоступно", "取得できません", "사용 불가" }[index],
            "none" => new[] { "None detected", "未检测到", "Не обнаружено", "検出されませんでした", "감지되지 않음" }[index],
            "charging" => new[] { "AC connected", "已接通电源", "Питание от сети", "電源に接続中", "전원 연결됨" }[index],
            "discharging" => new[] { "On battery", "使用电池", "Питание от батареи", "バッテリー使用中", "배터리 사용 중" }[index],
            "free" => new[] { "free", "可用", "свободно", "空き", "사용 가능" }[index],
            "uptime" => new[] { "Uptime", "运行时间", "Время работы", "稼働時間", "가동 시간" }[index],
            "language" => new[] { "Language", "界面语言", "Язык", "言語", "언어" }[index],
            "interval" => new[] { "Sampling interval (seconds)", "采样间隔（秒）", "Интервал опроса (секунды)", "更新間隔（秒）", "갱신 간격(초)" }[index],
            "save" => new[] { "Save", "保存", "Сохранить", "保存", "저장" }[index],
            "local" => new[] { "Local monitoring · click a card for details", "本地监控 · 点击卡片查看详情", "Локальный мониторинг · нажмите карточку", "ローカル監視 · カードをクリックして詳細を表示", "로컬 모니터링 · 카드를 클릭해 상세 보기" }[index],
            "limits" => new[] { "Hardware temperatures and SMART health are not collected on Windows.", "Windows 版暂不采集硬件温度和 SMART 健康数据。", "В Windows температура и SMART пока не считываются.", "Windows 版では温度と SMART 情報は取得しません。", "Windows에서는 온도 및 SMART 상태를 수집하지 않습니다." }[index],
            "counters" => new[] { "Interface totals since the adapter counters were reset; virtual/VPN adapters are listed separately.", "总量为接口计数器重置以来的数据；虚拟/VPN 接口单独列出。", "Итоги с момента сброса счётчиков; VPN и виртуальные адаптеры показаны отдельно.", "合計はカウンターのリセット以降の値です。VPN・仮想アダプターは個別に表示します。", "합계는 인터페이스 카운터 초기화 이후의 값입니다. VPN 및 가상 어댑터는 별도로 표시됩니다." }[index],
            "error" => new[] { "Sampling failed; retrying on the next interval.", "采集失败，将在下个周期重试。", "Ошибка опроса. Повтор при следующем обновлении.", "取得に失敗しました。次回の更新で再試行します。", "수집에 실패했습니다. 다음 갱신 시 다시 시도합니다." }[index],
            "saveError" => new[] { "Could not save settings.", "无法保存设置。", "Не удалось сохранить настройки.", "設定を保存できませんでした。", "설정을 저장할 수 없습니다." }[index],
            _ => key
        };
    }
}
