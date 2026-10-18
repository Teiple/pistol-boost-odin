package external

import "core:strings"
import "core:fmt"
import main ".."
import "core:os"


Seperated_Lang :: enum {
    SimplifiedChinese = cast(int)main.Language.SimplifiedChinese,
    Japanese          = cast(int)main.Language.Japanese,
}

@(rodata)
lang_exports := [Seperated_Lang]string {
    .SimplifiedChinese = #directory + "/loc_subset_sc.txt",
    .Japanese          = #directory + "/loc_subset_jp.txt",
}

main :: proc() {
    for lang in Seperated_Lang {    
        sb : strings.Builder 
        strings.builder_init(&sb)
        defer strings.builder_destroy(&sb)

        for trans, term in main.loc_map[main.Language(lang)] {
            fmt.sbprintln(&sb, trans)
        }
        
        err := os.write_entire_file_from_string(
            lang_exports[lang],
            strings.to_string(sb)
        )
        
        if err != nil {
            panic("Error writing file!")
        }
    } 
}