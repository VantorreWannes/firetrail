#!/usr/bin/env fish

mkdir -p data

function bench -a file
    set name (path change-extension '' $file)
    set source_dir "data"
    set target_dir "/tmp/bench/$name"
    set source "$source_dir/$file"
    set target "$target_dir/$file"

    rm -rf $target_dir

    mkdir -p $source_dir
    mkdir -p $target_dir

    cp $source $target

    firetrail red encode "$target" "$target.ftr" --export "$target.ftr.lut"
    du -ba "$target.ftr.lut"

    poop "firetrail red encode $target $target.ftr"
    du -ba "$target.ftr"
    poop "firetrail orange encode $target $target.fto"
    du -ba "$target.fto"
    poop "firetrail white encode $target $target.ftw --import $target.ftr.lut"
    du -ba "$target.ftw"

    poop "firetrail red decode $target.ftr $target.bak"
    du -ba "$target.ftr"
    poop "firetrail orange decode $target.fto $target.bak"
    du -ba "$target.fto"
    poop "firetrail white decode $target.ftw $target.bak --import $target.ftr.lut"
    du -ba "$target.ftw"

    poop "zstd -f -T1 --fast=5 $target"
    du -ba "$target.zst"
    poop "lz4 -f -T1 --fast=20 $target"
    du -ba "$target.lz4"

    poop "zstd -f -d -T1 --fast=5 $target.zst"
    du -ba "$target.zst"
    poop "lz4 -f -d -T1 --fast=20 $target.lz4"
    du -ba "$target.lz4"
end

bench enwik9 | tee data/bench-enwik9.log
bench silesia.tar | tee data/bench-silesia.log
