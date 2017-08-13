#!/bin/bash

hash_sum=sha256sum

simple_name='simple-icons'
simple_source_dir="source/$simple_name"
simple_gen_dir="gen/$simple_name"
simple_icons_dir="icons/$simple_name"

mini_name='minimalistic-icons'
mini_source_dir="source/$mini_name"
mini_gen_dir="gen/$mini_name"
mini_icons_dir="icons/$mini_name"

needed_icons=$(node generator.js fill < icons.json | sort -u)

function get_color() {
    grep -Eo '(rect|polygon)[^#]+fill="#[0-9a-fA-F]{6}"' $1 | grep -Eo '#.{6}'
}

function validate_sums() {
    if [[ -f $1 ]] && [[ -f $2 ]]
    then
        sum="$(tail -1 $2 | grep -Eo '\w+' | head -1)"
        [[ "$($hash_sum $1 | grep -Eo '\w+' | head -1)" = "$sum" ]]
    else
        false
    fi
}

function comment_sum() {
    echo "<!-- $($hash_sum $1) -->"
}

mkdir -p {$simple_gen_dir,$simple_icons_dir,$mini_gen_dir,$mini_icons_dir}

for file in $(ls $simple_icons_dir)
do
    if [[ ! -f $simple_source_dir/$file ]] && [[ ! -f $simple_gen_dir/$file ]]
    then
        echo "Cleaning up unused simple icon $file"
        rm -f $simple_icons_dir/$file
    fi
done

for file in $(ls $simple_gen_dir)
do
    if [[ $file != *.folder.expanded.svg ]] || [[ ! -f $simple_source_dir/${file/.expanded/} ]] || [[ -f $simple_source_dir/$file ]]
    then
        echo "Cleaning up unused simple icon $file"
        rm -f $simple_gen_dir/$file
    fi
done

for file in $( (ls $mini_gen_dir && ls $mini_icons_dir) | sort -u)
do
    if [[ ! $file = *.light.svg ]] && [[ -z $(echo $needed_icons | grep -E "\\b$file\\b") ]]
    then
        echo "Cleaning up unused minimalistic icon $file"
        rm -f {$mini_gen_dir,$mini_icons_dir}/{$file,${file/.svg/.light.svg}}
    fi
done

for theme_source_dir in $mini_source_dir $simple_source_dir
do
    echo "Beautifying icons from $theme_source_dir"
    ./node_modules/.bin/svgo --config=.svgo.yml --multipass -f $theme_source_dir > /dev/null
done

for folder in $(ls $simple_source_dir/*.folder.svg)
do
    expanded_folder=${folder/.svg/.expanded.svg}
    gen_folder=$simple_gen_dir/$(basename $expanded_folder)

    if ! validate_sums $folder $gen_folder && [[ ! -f $expanded_folder ]]
    then
        echo "Generating simple $(basename $expanded_folder)"
        old_color=$(get_color $simple_source_dir/folder.expanded.svg)
        new_color=$(get_color $folder)
        cp $simple_source_dir/folder.expanded.svg $gen_folder
        sed -ri "s/$old_color/$new_color/g" $gen_folder
        comment_sum $folder >> $gen_folder
    fi
done

for file in $needed_icons
do
    simple_dir=$simple_source_dir

    if [[ -f $simple_gen_dir/$file ]]
    then
        simple_dir=$simple_gen_dir
    fi

    if [[ -f $mini_source_dir/$file ]]
    then
        file_dir=$mini_source_dir
        rm -f $mini_gen_dir/$file
    else
        file_dir=$mini_gen_dir

        if ! validate_sums $simple_dir/$file $mini_gen_dir/$file
        then
            echo "Generating minimalistic $file"
            node generator.js gen < $simple_dir/$file > $mini_gen_dir/$file
            comment_sum $simple_dir/$file >> $mini_gen_dir/$file
        fi
    fi

    light_file=${file/.svg/.light.svg}

    if ! validate_sums $file_dir/$file $mini_gen_dir/$light_file
    then
        echo "Generating minimalistic $light_file"
        node generator.js light < $file_dir/$file > $mini_gen_dir/$light_file
        comment_sum $file_dir/$file >> $mini_gen_dir/$light_file
    fi
done

for theme_name in $mini_name $simple_name
do
    theme_source_dir=source/$theme_name
    theme_gen_dir=gen/$theme_name
    theme_icon_dir=icons/$theme_name
    icon_list="$(ls $theme_source_dir) $(ls $theme_gen_dir)"
    svgo_cmd="./node_modules/.bin/svgo --multipass -o $theme_icon_dir"

    mkdir -p $theme_icon_dir
    echo "Writing $theme_name.json"
    node generator.js json $theme_icon_dir $(echo $icon_list | sort -u) < icons.json > $theme_name.json
    echo "Optimizing icons from $theme_source_dir"
    $svgo_cmd -f $theme_source_dir > /dev/null
    echo "Optimizing icons from $theme_gen_dir"
    $svgo_cmd -f $theme_gen_dir > /dev/null
done

echo 'Done'
