#!/bin/bash

echo "=== Testing Fan Commands ==="
echo

# Test getPwm function
echo "1. Testing getPwm (should return PWM value 0-255):"
getPwm() {
    output=$(/run/current-system/sw/bin/liquidctl status 2>/dev/null)
    echo "Full output: $output"
    # Simple regex: look for "Fan speed 1" followed by non-digits, then capture the number
    if [[ $output =~ Fan\ speed\ 1[^0-9]+([0-9]+) ]]; then
        rpm=${BASH_REMATCH[1]}
        echo "Raw RPM: $rpm"
        pwm=$((rpm * 255 / 2000))
        echo "Calculated PWM: $pwm"
    else
        echo "No fan speed found, returning 0"
        pwm=0
    fi
    echo $pwm
}

current_pwm=$(getPwm)
echo "Current PWM: $current_pwm"
echo

# Test getRpm function
echo "2. Testing getRpm (should return RPM value):"
getRpm() {
    output=$(/run/current-system/sw/bin/liquidctl status 2>/dev/null)
    # Simple regex: look for "Fan speed 1" followed by non-digits, then capture the number
    if [[ $output =~ Fan\ speed\ 1[^0-9]+([0-9]+) ]]; then
        rpm=${BASH_REMATCH[1]}
        echo $rpm
    else
        echo "0"
    fi
}

current_rpm=$(getRpm)
echo "Current RPM: $current_rpm"
echo

# Test setPwm function
echo "3. Testing setPwm (setting fan to 50% = PWM 127):"
setPwm() {
    local pwm=$1
    percent=$((pwm * 100 / 255))
    echo "Setting fan to $percent% (PWM: $pwm)"
    /run/current-system/sw/bin/liquidctl set fan1 speed $percent
}

echo "Setting fan to 50%..."
setPwm 127
sleep 2

echo "Checking PWM after setting to 50%..."
new_pwm=$(getPwm)
echo "New PWM: $new_pwm"
echo

echo "Checking RPM after setting to 50%..."
new_rpm=$(getRpm)
echo "New RPM: $new_rpm"
echo

# Test another PWM value
echo "4. Testing setPwm (setting fan to 25% = PWM 64):"
echo "Setting fan to 25%..."
setPwm 64
sleep 2

echo "Checking PWM after setting to 25%..."
final_pwm=$(getPwm)
echo "Final PWM: $final_pwm"
echo

echo "Checking RPM after setting to 25%..."
final_rpm=$(getRpm)
echo "Final RPM: $final_rpm"
echo

echo "=== Test Complete ==="
