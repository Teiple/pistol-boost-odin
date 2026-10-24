package external

import "core:strings"
import "core:fmt"
import main ".."
import "core:os"


Seperated_Lang :: enum {
    Simplified_Chinese = cast(int)main.Language.Simplified_Chinese,
    Japanese          = cast(int)main.Language.Japanese,
}

@(rodata)
lang_exports := [Seperated_Lang]string {
    .Simplified_Chinese = #directory + "/loc_subset_sc.txt",
    .Japanese          = #directory + "/loc_subset_jp.txt",
}

main :: proc() {
    language_selections := main.LANGUAGE_SELECTIONS
    for lang in Seperated_Lang {    
        sb : strings.Builder 
        strings.builder_init(&sb)
        defer strings.builder_destroy(&sb)

        for trans, term in main.loc_map[main.Language(lang)] {
            fmt.sbprintln(&sb, trans)
        }
        
        fmt.sbprintln(&sb, language_selections[main.Language(lang)])
        
        err := os.write_entire_file_from_string(
            lang_exports[lang],
            strings.to_string(sb)
        )
        
        if err != nil {
            panic("Error writing file!")
        }
    } 
}