#!/usr/bin/env fish

mkdir -p data

set script_dir (path dirname (status filename))
set root_dir (path normalize "$script_dir/..")

function validate -a file
    set name (path change-extension '' $file)
    set source_dir "$root_dir/data"
    set target_dir "/tmp/bench/$name"
    set source "$source_dir/$file"
    set target "$target_dir/$file"

    rm -rf $target_dir

    mkdir -p $source_dir
    mkdir -p $target_dir

    cp $source $target

    firetrail red encode "$target" "$target.ftr" --export "$target.ftr.lut"

    firetrail red encode "$target" "$target.ftr"
    cmp $target $source
    firetrail orange encode "$target" "$target.fto"
    cmp $target $source
    firetrail white encode "$target" "$target.ftw" --import "$target.ftr.lut"
    cmp $target $source
    firetrail red decode "$target.ftr" "$target.bak"
    cmp $target "$target.bak"
    firetrail orange decode "$target.fto" "$target.bak"
    cmp $target "$target.bak"
    firetrail white decode "$target.ftw" "$target.bak" --import "$target.ftr.lut"
    cmp $target "$target.bak"
end

validate enwik9 | tee data/validate-enwik9.log
validate silesia.tar | tee data/validate-silesia.log
