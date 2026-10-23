#!/bin/sh
set -eu

# Some command-line-only Swift 6.4 installs do not register the bundled Testing
# macro plugin with the default build engine. Full Xcode needs no extra flags.
task_developer_dir="$(xcode-select -p)"
task_testing_plugin="$task_developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
case "$task_developer_dir" in
    */CommandLineTools)
        if [ -f "$task_testing_plugin" ]; then
            exec swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$task_testing_plugin" "$@"
        fi
        ;;
esac
exec swift test "$@"
