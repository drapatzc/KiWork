#!/bin/bash

# Function to clear derived data
clear_derived_data() {
    echo "Clearing Derived Data..."
    rm -rf ~/Library/Developer/Xcode/DerivedData
    echo "Derived Data cleared!"
}

# Function to clear module cache
clear_module_cache() {
    echo "Clearing Module Cache..."
    rm -rf ~/Library/Developer/Xcode/ModuleCache
    echo "Module Cache cleared!"
}

# Function to clear simulator cache
clear_simulator_cache() {
    echo "Clearing Simulator Cache..."
    rm -rf ~/Library/Developer/CoreSimulator/Caches
    echo "Simulator Cache cleared!"
}

# Function to close Xcode
close_xcode() {
    echo "Closing Xcode..."
    osascript -e 'quit app "Xcode"'
    echo "Xcode closed!"
}

# Function to restart Xcode
restart_xcode() {
    close_xcode
    echo "Reopening Xcode..."
    open -a "$(mdfind -name 'Xcode' | grep '15.4.0' | head -n 1)"
    echo "Xcode restarted!"
}

# Function to clear Derived Data and restart Xcode
clear_derived_data_and_restart() {
    close_xcode
    clear_derived_data
    restart_xcode
}

# Menu options
while true; do
    echo "Select an option:"
    echo "1) Clear Derived Data"
    echo "2) Clear Module Cache"
    echo "3) Clear Simulator Cache"
    echo "4) Close Xcode"
    echo "5) Restart Xcode"
    echo "6) Clear Derived Data and Restart Xcode"
    echo "7) Exit"

    read -p "Enter your choice [1-7]: " choice
    case $choice in
        1) clear_derived_data ;;
        2) clear_module_cache ;;
        3) clear_simulator_cache ;;
        4) close_xcode ;;
        5) restart_xcode ;;
        6) clear_derived_data_and_restart ;;
        7) echo "Goodbye!" ; exit ;;
        *) echo "Invalid option, please try again." ;;
    esac
done
