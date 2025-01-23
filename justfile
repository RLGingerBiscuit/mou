set shell := ['bash', '-uc']
set windows-shell := ['cmd', '/c']

name := 'mou'
src := 'src/'
# name := 'noise'
# src := 'src/noise'
ext := if os_family() == 'windows' { '.exe' } else { '' }
out_dir := 'bin'
pkg_dir := 'packaged'
odin_exe := 'odin'
odin_args := '-vet -vet-cast -vet-tabs -strict-style -collection:third=third/'

# Default recipe which runs `just build-release`
default: build-release

# Cleans the build directory
clean:
	@just _clean-{{os_family()}}

_clean-windows:
	-del /F /Q {{out_dir}}\{{name}}{{ext}} >nul 2>nul
	-del /F /Q {{out_dir}}\{{name}}_debug{{ext}} >nul 2>nul
	-rmdir /S /Q {{pkg_dir}} >nul 2>nul
	-del /F /Q atlas.bmp font.bmp packaged.zip >nul 2>nul

_clean-unix:
	-rm -rf {{out_dir}}/*
	-rm -rf {{pkg_dir}}
	-rm -f *.bmp packaged.zip

# Compiles with debug profile
build-debug *args:
	{{odin_exe}} build {{src}} -debug -out:{{out_dir}}/{{name}}_debug{{ext}} {{odin_args}} {{args}}

# Compiles with release profile
build-release *args:
	{{odin_exe}} build {{src}} -out:{{out_dir}}/{{name}}{{ext}} {{odin_args}} {{args}}
alias build := build-release

# Runs `odin check`
check:
	{{odin_exe}} check {{src}} {{odin_args}}

# Runs the application with debug profile
run-debug *args:
	{{odin_exe}} run {{src}} -debug -out:{{out_dir}}/{{name}}_debug{{ext}} {{odin_args}} {{args}}
alias debug := run-debug

# Runs the application with release profile
run-release *args:
	{{odin_exe}} run {{src}} -out:{{out_dir}}/{{name}}{{ext}} {{odin_args}} {{args}}
alias run := run-release

# Packages a release build of the application into a 'packaged' folder
package: build-release
	@just _package-{{os_family()}}

_package-windows:
	-rmdir /S /Q {{pkg_dir}} >nul 2>nul
	-del /S /Q {{pkg_dir}}.zip >nul 2>nul
	-mkdir {{pkg_dir}} >nul 2>nul
	xcopy /Q /Y {{out_dir}}\{{name}}{{ext}} {{pkg_dir}}
	xcopy /Q /Y /S /I assets\ {{pkg_dir}}\assets
	7z a -y {{pkg_dir}}.zip .\{{pkg_dir}}\*

_package-unix:
	-rm -rf {{pkg_dir}}
	-mkdir -p {{pkg_dir}}
	cp -fr {{out_dir}}/{{name}}{{ext}} assets {{pkg_dir}}/
	7z a -y {{pkg_dir}}.zip ./{{pkg_dir}}/*
