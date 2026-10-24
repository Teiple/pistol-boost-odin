package main
import "core:slice"

Language :: enum {
    English,
    Vietnamese,
    Simplified_Chinese,
    Japanese,
}

Loc_Term :: enum {
    Undefined,
    New_Game,
    Continue,
    Exit,
    Yes,
    No,
    On,
    Off,
    Exit_Confirmation,
    Main_Menu,
    Settings,
    About,
    Archivements,
    Gameplay,
    Audio,
    Controls,
    Graphics,
    Language,
    Back,
    Apply,
    Defaults,
    Resolution,
    Fullscreen,
    Brightness,
    Gamma,
    Particles,
    Decals,
}

LANGUAGE_SELECTIONS : [Language]string : {
    .English           = "English",   
    .Vietnamese        = "Tiếng Việt",
    .Simplified_Chinese = "简体中文",   
    .Japanese          = "日本語",     
}

UNDEFINED_TERM :: "<UNDEFINED!>"

@(rodata)
loc_map : [Language][Loc_Term]string = {
    .English = {
        .Undefined = UNDEFINED_TERM,
        .New_Game = "New Game",
        .Continue = "Continue",
        .Exit = "Exit?",
        .Yes = "Yes",
        .No = "No",
        .On = "On",
        .Off = "Off",
        .Exit_Confirmation = "Are you sure you want to exit the program?",
        .Main_Menu = "Main Menu",
        .Settings = "Settings",
        .About = "About",
        .Archivements = "Archivements",
        .Gameplay = "Gameplay", 
        .Audio = "Audio",
        .Controls = "Controls",
        .Graphics = "Graphics",
        .Language = "Language",
        .Back = "< Back",
        .Apply = "Apply",
        .Defaults = "Defaults",
        .Resolution = "Resolution",
        .Fullscreen = "Fullscreen",
        
        .Brightness = "Brightness",
        .Gamma = "Gamma",
        .Particles = "Particles",
        .Decals = "Decals",
    },
    .Simplified_Chinese = {
        .Undefined = UNDEFINED_TERM,
        .New_Game = "新游戏",
        .Continue = "继续",
        .Exit = "退出？",
        .Yes = "是",
        .No = "否",
        .On = "开启",
        .Off = "关闭",
        .Exit_Confirmation = "确定要退出程序吗？",
        .Main_Menu = "主菜单",
        .Settings = "设置",
        .About = "关于",
        .Archivements = "成就",
        .Gameplay = "游戏玩法",
        .Audio = "音频",
        .Controls = "操作",
        .Graphics = "画面",
        .Language = "语言",
        .Back = "< 返回",
        .Apply = "申请",
        .Defaults = "默认值",
        .Resolution = "分辨率",
        .Fullscreen = "全屏",
        
        .Brightness = "亮度",
        .Gamma = "伽马值",
        .Particles = "粒子",
        .Decals = "贴花",
    },
    .Vietnamese = {
        .Undefined = UNDEFINED_TERM,
        .New_Game = "Game mới",
        .Continue = "Tiếp tục",
        .Exit = "Thoát?",
        .Yes = "Có",
        .No = "Không",
        .On = "Bật",
        .Off = "Tắt",
        .Exit_Confirmation = "Bạn có chắc muốn thoát chương trình?",
        .Main_Menu = "Menu chính",
        .Settings = "Cài đặt",
        .Archivements = "Thành tựu",
        .About = "Thông tin",
        .Gameplay = "Lối chơi", 
        .Audio = "Âm thanh",
        .Controls = "Điều khiển",
        .Graphics = "Đồ họa",
        .Language = "Ngôn ngữ",
        .Back = "< Quay lại",
        .Apply = "Áp dụng",
        .Defaults = "Mặc định",
        .Resolution = "Độ phân giải",
        .Fullscreen = "Toàn màn hình",
        
        .Brightness = "Độ sáng",
        .Gamma = "Gamma",
        .Particles = "Hiệu ứng hạt",
        .Decals = "Đề-can",
    },
    .Japanese = {
        .Undefined = UNDEFINED_TERM,
        .New_Game = "新しいゲーム",
        .Continue = "続ける",
        .Exit = "終了しますか?",
        .Yes = "はい",
        .No = "いいえ",
        .On = "オン",
        .Off = "オフ",
        .Exit_Confirmation = "プログラムを終了してもよろしいですか?",
        .Main_Menu = "メインメニュー",
        .Settings = "設定",
        .About = "バージョン情報",
        .Archivements = "アーカイブ",
        .Gameplay = "ゲームプレイ",
        .Audio = "オーディオ",
        .Controls = "コントロール",
        .Graphics = "グラフィック",
        .Language = "言語",
        .Back = "< 戻る",
        .Apply = "適用する",
        .Defaults = "デフォルト",
        .Resolution = "解像度",
        .Fullscreen = "全画面表示",
        
        .Brightness = "明るさ",
        .Gamma = "ガンマ",
        .Particles = "パーティクル",
        .Decals = "デカール",
    },
}

Lang_Font_Declare :: struct {
    ttf_data     : []byte,
    atlas_width  : i32,
    atlas_height : i32,
    base_size    : f32,
}

DEFAULT_FONT_BASE_SIZE :: 32

// TODO: Multiple font id style for each lang font
@(rodata)
lang_font_declares : [Language]Lang_Font_Declare = {
    .English..=.Vietnamese = {
        ttf_data     = #load("assets/fonts/NotoSansMono_SemiCondensed-Regular.ttf"),
        atlas_width  = 256,
        atlas_height = 128,
    },
    .Simplified_Chinese = {
        ttf_data     = #load("assets/fonts/NotoSansMonoCJKsc-Subset.ttf"),
        atlas_width  = 256,
        atlas_height = 256,
    },
    .Japanese = {
        ttf_data     = #load("assets/fonts/NotoSansMonoCJKjp-Subset.ttf"),
        atlas_width  = 256,
        atlas_height = 256,
    },
} 

load_lang_font_configs :: proc() -> []Lang_Font_Config {
    font_cfgs := make([]Lang_Font_Config, len(Language))
    language_selections := LANGUAGE_SELECTIONS
    
    for lang_decl, lang in lang_font_declares {
        non_ascii_runes := make([dynamic]rune)
        
        for trans in loc_map[lang] {
            for r in trans {
                char := int(r)
                // ascii range always loaded contiguously
                if char >= 32 && char <= 126 {
                    continue
                }
                if slice.contains(non_ascii_runes[:], r) {
                    continue
                }

                append(&non_ascii_runes, r)
            }
        }

        for r in language_selections[lang] {
            char := int(r)

            if char >= 32 && char <= 126 {
                continue
            }

            if slice.contains(non_ascii_runes[:], r) {
                continue
            }
            
            append(&non_ascii_runes, r)
        }

        font_cfgs[lang] = {            
            language        = lang,
            non_ascii_runes = non_ascii_runes,
            ttf_data        = lang_decl.ttf_data,
            atlas_width     = lang_decl.atlas_width,
            atlas_height    = lang_decl.atlas_height,
            base_size       = (
                lang_decl.base_size <= 0 ?
                DEFAULT_FONT_BASE_SIZE :
                lang_decl.base_size
            )
        }
    }
    
    return font_cfgs[:]
}

unload_lang_font_configs :: proc(font_cfgs : []Lang_Font_Config) {
    for config in font_cfgs {
        delete(config.non_ascii_runes)
    }
    delete(font_cfgs)
}