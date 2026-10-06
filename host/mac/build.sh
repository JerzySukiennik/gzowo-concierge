#!/bin/zsh
set -e
cd "$(dirname "$0")/../.."
APP=bin/ConciergeCal.app
swiftc -O host/mac/cal.swift -o /tmp/concierge-cal-bin
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp /tmp/concierge-cal-bin $APP/Contents/MacOS/ConciergeCal
cp host/mac/cal-info.plist $APP/Contents/Info.plist
codesign -s - --force --deep $APP
echo "built $APP"
