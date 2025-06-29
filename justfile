set shell := ['bash', '-uc']
set windows-shell := ['cmd', '/c']

name := 'mou'
src := 'src/'
ext := if os_family() == 'windows' { '.exe' } else { '' }
out_dir := 'bin'
prof_dir := 'prof'
pkg_dir := 'packaged'
odin_exe := 'odin'
odin_args := '-vet -vet-cast -vet-tabs -strict-style -collection:third=third/ -keep-executable'

# Default recipe which runs `just build-release`
default: build-release

_init:
	@just _init-{{os_family()}}

_init-windows:
	-mkdir {{out_dir}} >nul 2>nul
	-mkdir {{prof_dir}} >nul 2>nul

_init-unix:
	-mkdir -p {{out_dir}} >/dev/null 2>&1
	-mkdir -p {{prof_dir}} >/dev/null 2>&1

# Cleans all output files (build directory, packaged outputs, etc.)
clean:
	@just _clean-{{os_family()}}

_clean-windows:
	-rmdir /S /Q {{out_dir}} {{pkg_dir}} {{prof_dir}} >nul 2>nul
	-del /F /Q *.bmp *.zip *.tar* >nul 2>nul

_clean-unix:
	-rm -fr {{out_dir}} {{pkg_dir}} {{prof_dir}} >/dev/null 2>&1
	-rm -f *.bmp *.zip *.tar* >/dev/null 2>&1

# Compiles with debug profile
build-debug *args: _init
	{{odin_exe}} build {{src}} -debug -out:{{out_dir}}/{{name}}_debug{{ext}} {{odin_args}} {{args}}

# Compiles with release profile
build-release *args: _init
	{{odin_exe}} build {{src}} -out:{{out_dir}}/{{name}}{{ext}} {{odin_args}} {{args}}
alias build := build-release

# Runs `odin check`
check: _init
	{{odin_exe}} check {{src}} {{odin_args}}

# Runs the application with debug profile
run-debug *args: _init
	{{odin_exe}} run {{src}} -debug -out:{{out_dir}}/{{name}}_debug{{ext}} {{odin_args}} {{args}}
alias debug := run-debug

# Runs the application with release profile
run-release *args: _init
	{{odin_exe}} run {{src}} -out:{{out_dir}}/{{name}}{{ext}} {{odin_args}} {{args}}
alias run := run-release

# Packages a release build of the application into a 'packaged' folder
package: build-release
	@just _package-{{os_family()}}

_package-windows:
	-rmdir /S /Q {{pkg_dir}} >nul 2>nul
	-del /S /Q {{pkg_dir}}-{{os()}}.zip >nul 2>nul
	-mkdir {{pkg_dir}} >nul 2>nul
	xcopy /Q /Y {{out_dir}}\{{name}}{{ext}} {{pkg_dir}}
	xcopy /Q /Y /S /I assets\ {{pkg_dir}}\assets
	7z a -y {{pkg_dir}}-{{os()}}.zip .\{{pkg_dir}}\*

_package-unix:
	-rm -fr {{pkg_dir}} {{pkg_dir}}-{{os()}}.tar.gz >/dev/null 2>&1
	-mkdir -p {{pkg_dir}} >/dev/null 2>&1
	cp -r {{out_dir}}/{{name}}{{ext}} assets {{pkg_dir}}/
	tar cf {{pkg_dir}}-{{os()}}.tar.gz -C {{pkg_dir}} .
