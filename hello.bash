nvim -N -u NONE -n -c 'set nomore' -S <(echo -E ':%s/^plugins\(.*$\n^\)\{-}}//e') "$HOME/sample/app/build.gradle.kts"
