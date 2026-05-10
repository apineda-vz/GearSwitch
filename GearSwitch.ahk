; =====================================================
; Gear System: Gear 1–Gear 7
; Version: 2025/11/25/15/23
; (modified: Shift+E sends a single E per press — collectedE now only resets on +e up)
; (added: potion cooldown display when using potion in Gear1 fight mode via WheelDown)
; (modified: Gear 6 now spam-left-click toggle via Middle Click at 5 ms)
; (modified: WheelDown in Gear1 now does "f,1,f,wait1s,1" with immediate 'f' on repeated presses)
; (modified: abort pending Gear1 WheelDown sequence when switching gear or enabling Fight Mode)
; (modified: removed map flicker; 0 and Space are now back to normal)
; (modified: E is now pressed once per detection event — no continuous E-spam after detection)
; (modified: appended Backspace to end of Gear1 WheelDown sequence)
; (added: 0 key toggle -> when ON, Gear1 fight-mode uses "6" instead of "2")
; (added: left-click behavior when zeroToggle ON in Gear1 fight mode with configurable delay)
; (added: Right Alt toggle for reload-in-sequence; ON by default)
; (modified: register/unregister hotkey changed to Left Ctrl + X to avoid accidental triggers)
; (added: Left Alt push-to-talk press/release edge sequences with mouse restore and post-restore nudge)
; (modified: q hotkey — send only 'm' unless an input control has focus, in which case send 'q'; fixed to allow typing q while paused/chatting)
; =====================================================

#NoEnv
#Persistent
#SingleInstance Force
#MaxHotkeysPerInterval 999
#InstallKeybdHook
#InstallMouseHook
#UseHook
#IfWinActive ahk_exe RobloxPlayerBeta.exe
SetBatchLines, -1
ListLines, Off
SetKeyDelay, -1, -1
SetWinDelay, 0
SendMode, Input
Process, Priority,, High

registered := false
regX := 0
regY := 0
regColor := ""
detected := false
watching := false
watchingE := false
collected := false
detectedE := false        ; <-- edge-detect flag for E (one E per detection)
SetTimer, PixelWatch, Off

CoordMode, Pixel, Screen
CoordMode, Mouse, Screen

saveFile := A_ScriptDir "\pixel_data.ini"

; =====================================================
; Push-to-talk edge flag (Left Alt)
; - used to ensure the sequence only fires on the press edge and the release edge
; - prevMouseX/Y store the mouse position before LAlt press and restore after release
; - postRestoreDelay (ms) is the sleep after restore before moving 1 pixel (user requested)
; =====================================================
lAltPressed := false
prevMouseX := 0
prevMouseY := 0
postRestoreDelay := 20

; =====================================================
; CUSTOM COLLECT TIMES
; =====================================================
gear1CollectTime := 500
gear5CollectTime := 50

; =====================================================
; DANCE LIST (Gear 7) and remembered index
; =====================================================
danceList := [ " dance2", " wave", " point", " laugh", " cheer", " dance" ]
danceIndex := 1

; =====================================================
; POTION COOLDOWN GUI STATE
; (VERY SMALL FIX)
; =====================================================
potionCDActive := false
potionCDEnd := 0
PotionText := ""

; =====================================================
; GEAR 6 SPAM STATE
; =====================================================
gear6Spamming := false  ; toggled by middle click when in gear 6
; spam interval in ms
gear6SpamInterval := 5

; =====================================================
; GEAR1 SEQUENCE STATE (for WheelDown sequence)
; =====================================================
gear1SeqRunning := false  ; true while the "1,f,wait,1" sequence is pending/active

; =====================================================
; ZERO TOGGLE (0 key) - off by default
; when true: Gear1 fight mode uses "6" instead of "2"
; =====================================================
zeroToggle := false
; =====================================================
; ZERO LEFT-CLICK DELAY (ms) used when zeroToggle is ON and you left-click in Gear1 fight mode
; adjustable: change this value to tune timing
; =====================================================
zeroLeftDelay := 110

; =====================================================
; RELOAD TOGGLE (Right Alt) - ON by default
; When true: DoRangedShot will include an 'r' (reload) in the sequence
; When false: DoRangedShot will skip sending 'r'
; =====================================================
reloadToggle := true

; =====================================================
; LOAD SAVED PIXEL ON STARTUP
; =====================================================
if (FileExist(saveFile)) {
    IniRead, regX, %saveFile%, Pixel, X, 0
    IniRead, regY, %saveFile%, Pixel, Y, 0
    IniRead, regColor, %saveFile%, Pixel, Color, ""
    if (regX && regY && regColor != "") {
        registered := true
        ShowFloatText("Loaded pixel " regX "," regY " #" regColor)
        DotX := regX + 1, DotY := regY + 1
        Gui, RegDot:Destroy
        Gui, RegDot:+AlwaysOnTop -Caption +ToolWindow +LastFound +E0x20
        Gui, RegDot:Color, FF0000
        Gui, RegDot:Add, Text, w1 h1
        Gui, RegDot:Show, x%DotX% y%DotY% NoActivate
    }
}

; =====================================================
; FLOAT TEXT (now centered in the bottom half of the Roblox window)
; =====================================================
ShowFloatText(msg) {
    Gui, FloatMsg:Destroy

    ; Attempt to position relative to the Roblox window; fallback to screen if not found
    WinGetPos, wx, wy, ww, wh, ahk_exe RobloxPlayerBeta.exe
    if (ErrorLevel || !ww || !wh) {
        ; fallback to full screen center-bottom-half
        xCenter := A_ScreenWidth // 2
        yCenter := A_ScreenHeight * 3 // 4  ; 3/4 down = middle of bottom half
    } else {
        xCenter := wx + (ww // 2)
        yCenter := wy + (wh * 3 // 4)  ; middle of the lower half of the window
    }

    ; small floating text box
    width := 220
    height := 22
    xpos := xCenter - (width // 2)
    ypos := yCenter - (height // 2)

    Gui, FloatMsg:+AlwaysOnTop -Caption +ToolWindow +LastFound +E0x20
    Gui, FloatMsg:Color, 333333
    Gui, FloatMsg:Font, cWhite s10, Segoe UI
    Gui, FloatMsg:Add, Text, w%width% h%height% Center, %msg%
    Gui, FloatMsg:Show, x%xpos% y%ypos% NoActivate
    SetTimer, DestroyFloatMsg, -1000
}
DestroyFloatMsg:
Gui, FloatMsg:Destroy
return

; =====================================================
; POTION COOLDOWN UI (MINIMIZED)
; - very small width/height
; - minimal margin/padding
; - small font, white color
; =====================================================
StartPotionCooldown(durationSec := 6) {
    global potionCDActive, potionCDEnd, PotionText

    WinGetPos, wx, wy, ww, wh, ahk_exe RobloxPlayerBeta.exe
    if (ErrorLevel || (ww = "" && wh = "")) {
        xCenter := A_ScreenWidth // 2
        yCenter := A_ScreenHeight // 4
    } else {
        xCenter := wx + (ww // 2)
        yCenter := wy + (wh // 4)
    }

    Gui, PotionCD:Destroy
    Gui, PotionCD:+AlwaysOnTop -Caption +ToolWindow +LastFound +E0x20
    ; dark background but very small
    Gui, PotionCD:Color, 222222

    ; remove default padding/margin so GUI is tiny
    Gui, PotionCD:Margin, 0, 0

    ; very small readable font (adjust down if you still want smaller)
    Gui, PotionCD:Font, cWhite s9, Segoe UI

    ; single-token control name (vPotionText -> variable PotionText)
    Gui, PotionCD:Add, Text, vPotionText Center, % ""

    ; tiny window size
    width := 56
    height := 18

    xpos := xCenter - (width // 2)
    ypos := yCenter - (height // 2)

    Gui, PotionCD:Show, x%xpos% y%ypos% w%width% h%height% NoActivate

    ; set initial value immediately
    GuiControl,, PotionText, % durationSec

    potionCDEnd := A_TickCount + (durationSec * 1000)
    potionCDActive := true
    SetTimer, PotionCD_Update, 100
}

PotionCD_Update:
global potionCDActive, potionCDEnd
if (!potionCDActive) {
    SetTimer, PotionCD_Update, Off
    return
}
remaining := potionCDEnd - A_TickCount
if (remaining > 0) {
    seconds := (remaining + 999) // 1000
    GuiControl,, PotionText, %seconds%
} else {
    GuiControl,, PotionText, % "ready"
    potionCDActive := false
    SetTimer, PotionCD_Update, Off
    SetTimer, PotionCD_Destroy, -1000
}
return

PotionCD_Destroy:
Gui, PotionCD:Destroy
return

; -----------------------
; Quick tap / slight walk keys
; -----------------------
Numpad8::SendInput, {w down}{w up}
Numpad2::SendInput, {s down}{s up}
Numpad4::SendInput, {a down}{a up}
Numpad6::SendInput, {d down}{d up}
return

; -----------------------
; Register Pixel
; -----------------------
<^x::
if (paused)
    return
MouseGetPos, mx, my
PixelGetColor, pxColor, %mx%, %my%, RGB
StringUpper, pxColor, pxColor
StringTrimLeft, pxColor, pxColor, 2
if (!registered) {
    regX := mx, regY := my, regColor := pxColor
    registered := true, detected := false, collected := false
    ShowFloatText("Registered " regX "," regY " #" regColor)
    DotX := regX + 1, DotY := regY + 1
    Gui, RegDot:Destroy
    Gui, RegDot:+AlwaysOnTop -Caption +ToolWindow +LastFound +E0x20
    Gui, RegDot:Color, FF0000
    Gui, RegDot:Add, Text, w1 h1
    Gui, RegDot:Show, x%DotX% y%DotY% NoActivate

    IniWrite, %regX%, %saveFile%, Pixel, X
    IniWrite, %regY%, %saveFile%, Pixel, Y
    IniWrite, %regColor%, %saveFile%, Pixel, Color
} else {
    registered := false, regX := 0, regY := 0, regColor := ""
    detected := false, collected := false, watching := false, watchingE := false
    detectedE := false
    SetTimer, PixelWatch, Off
    Gui, RegDot:Destroy
    FileDelete, %saveFile%
    ShowFloatText("Pixel Unregistered (Saved data cleared)")
}
return

; -----------------------
; Shift+F: watching
; -----------------------
+f::
if (paused || !registered)
    return
if (currentGear = 1 && !fightMode) {
    watching := true, detected := false, collected := false
    SetTimer, PixelWatch, 1
    ShowFloatText("Watching pixel (Gear 1)...")
} else if (currentGear = 5) {
    watching := true, detected := false, collected := false
    SetTimer, PixelWatch, 1
    ShowFloatText("Watching pixel (Gear 5)...")
}
return

+f up::
watching := false
collected := false
if (!watchingE)
    SetTimer, PixelWatch, Off
return

~Shift up::
if (watching) {
    watching := false
    collected := false
    if (!watchingE)
        SetTimer, PixelWatch, Off
    ShowFloatText("Watching stopped (Shift released)")
}
return

; -----------------------
; Shift+E
; -----------------------
+e::
if (paused || !registered)
    return
if (currentGear = 1 && !fightMode) {
    watchingE := true
    detectedE := false        ; allow fresh detection when enabling
    SetTimer, PixelWatch, 1
    ShowFloatText("Watching pixel (Shift+E)...")
}
return

+e up::
watchingE := false
detectedE := false
if (!watching)
    SetTimer, PixelWatch, Off
return

; =====================================================
; PIXEL WATCH
; =====================================================
PixelWatch:
if (!registered || ( !watching && !watchingE ) || paused)
    return
PixelGetColor, curC, %regX%, %regY%, RGB
StringUpper, curC, curC
StringTrimLeft, curC, curC, 2

isMatch := (curC = regColor)

if (isMatch) {
    if (watching && !collected) {
        collected := true
        Gosub, CollectAction
        ShowFloatText("Detected - Collected!")
    }
    if (watchingE && !detectedE) {
        detectedE := true
        SendInput, e
        Sleep, 6
        ShowFloatText("Detected - E sent")
    }
} else {
    collected := false
    detectedE := false         ; reset edge flag when pixel no longer matches
}
return

DoRangedShot() {
    global zeroToggle, reloadToggle
    SendInput, 3
    Sleep, 40
    Click
    Sleep, 30
    ; send reload only if reloadToggle is true
    if (reloadToggle) {
        SendInput, r
        Sleep, 30
    }
    ; send 6 instead of 2 if zeroToggle is ON
    SendInput, % (zeroToggle ? "6" : "2")
    return
}

; =====================================================
; Right Alt toggle for reload-in-sequence
; Right Alt toggles reloadToggle (ON by default). Show float text.
; =====================================================
RAlt::
if (paused)
    return
reloadToggle := !reloadToggle
ShowFloatText("Reload in sequence: " (reloadToggle ? "ON" : "OFF"))
return

CollectAction:
global gear1CollectTime, gear5CollectTime
SendInput, {LButton down}
if (currentGear = 1)
    Sleep, %gear1CollectTime%
else if (currentGear = 5)
    Sleep, %gear5CollectTime%
else
    Sleep, 500
PixelGetColor, curC2, %regX%, %regY%, RGB
StringUpper, curC2, curC2
StringTrimLeft, curC2, curC2, 2
if (curC2 = regColor) {
    if (currentGear = 1) {
        if (fightMode)
            DoRangedShot()
        else {
            SendInput, 1
            Sleep, 10
            SendInput, f
            Sleep, 10
            SendInput, 1
        }
    } else if (currentGear = 5) {
        SendInput, 1
        Sleep, 10
        SendInput, f
        Sleep, 10
        SendInput, 4
    }
}
SendInput, {LButton up}
return

; =====================================================
; GEAR VARIABLES
; =====================================================
currentGear := 1
fightMode := false
paused := false
SetTimer, AutoEat, Off
SetTimer, AutoE, Off
eating := false
pressingE := false
lumberMode := 1
nightMode := true

; =====================================================
; F1–F7
; =====================================================
F1::SwitchGear(1)
F2::SwitchGear(2)
F3::SwitchGear(3)
F4::SwitchGear(4)
F5::SwitchGear(5)
F6::SwitchGear(6)
F7::SwitchGear(7)

SwitchGear(gear) {
    global currentGear, eating, pressingE, fightMode, lumberMode, nightMode, lastGear, paused, gear6Spamming, gear1SeqRunning, detectedE
    if (paused)
        return
    lastGear := currentGear
    ; if we are switching away from gear 6, ensure spam is stopped
    if (lastGear = 6 && gear != 6) {
        gear6Spamming := false
        SetTimer, Gear6Spam, Off
    }
    ; if switching away from Gear 1, abort any pending Gear1 sequence immediately
    if (lastGear = 1 && gear != 1) {
        gear1SeqRunning := false
        SetTimer, Gear1Seq_Runner, Off
        SetTimer, Gear1Seq_Final, Off
        detectedE := false        ; ensure no stale E-edge state
    }
    currentGear := gear
    SetTimer, AutoEat, Off
    SetTimer, AutoE, Off
    eating := false
    pressingE := false
    if (currentGear = 1) {
        ShowFloatText("Gear 1 (Normal)")
        fightMode := false
        SendInput, 1
        SendInput, 1
        SendInput, {Shift}
        if (lastGear = 2)
            SendInput, {LCtrl}
    } else if (currentGear = 2) {
        ShowFloatText("Gear 2 (Night)")
        nightMode := true
        SendInput, 5
        Sleep, 20
        Send, {LCtrl}
        Sleep, 20
        Send, {Shift down}
        Sleep, 20
        Send, {Esc}
        Sleep, 60
        Send, {Shift up}
        Sleep, 40
        Send, {Esc}
    } else if (currentGear = 3)
        ShowFloatText("Gear 3 (Auto-Eat)")
    else if (currentGear = 4)
        ShowFloatText("Gear 4 (E Spam)")
    else if (currentGear = 5) {
        ShowFloatText("Gear 5 (Lumber)")
        lumberMode := 1
        SendInput, 4
    } else if (currentGear = 6) {
        ; Ensure gear6 spamming is off when you switch into gear 6 (requires middle-click to toggle)
        gear6Spamming := false
        SetTimer, Gear6Spam, Off
        ShowFloatText("Gear 6 (Click Spam)")
    } else if (currentGear = 7)
        ShowFloatText("Gear 7 (Dance Mode)")
}

; =====================================================
; PAUSE
; - left click now unpauses as before, plus special zeroToggle behavior when in Gear1 fight mode
; =====================================================
~/::
    paused := true
    return

~Enter::
    paused := false
    return

~LButton::
    ; unpause on left click (same behavior as before)
    paused := false

    ; special behavior only when: Gear 1, fightMode ON, and zeroToggle ON
    if (currentGear = 1 && fightMode && zeroToggle) {
        ; press 2 first
        SendInput, 2
        Sleep, 8
        ; native left-click still occurs because of the ~ prefix - do NOT send an extra Click
        ; wait the configurable delay then press 6
        Sleep, %zeroLeftDelay%
        SendInput, 6
    }
return

; =====================================================
; ZERO TOGGLE (0 key) - toggles zeroToggle on/off
; =====================================================
~0::
if (paused)
    return
zeroToggle := !zeroToggle
ShowFloatText("Zero toggle " (zeroToggle ? "ON (use 6 in fight mode)" : "OFF (use 2 in fight mode)"))
return

; =====================================================
; MIDDLE CLICK
; =====================================================
MButton::
global fightMode, nightMode, lumberMode, eating, pressingE, paused, gear6Spamming, currentGear, gear6SpamInterval, gear1SeqRunning, detectedE, zeroToggle
if (paused)
    return
if (currentGear = 1) {
    fightMode := !fightMode

    ; if enabling fight mode, abort any pending Gear1 WheelDown sequence immediately
    if (fightMode) {
        gear1SeqRunning := false
        SetTimer, Gear1Seq_Runner, Off
        SetTimer, Gear1Seq_Final, Off
        detectedE := false    ; clear any pending/edge state for E
    }

    if (fightMode) {
        ; send 6 instead of 2 if zeroToggle is ON
        Send, % (zeroToggle ? "6" : "2")
        Sleep, 20
        Send, {LCtrl}
        Sleep, 20
        Send, {Shift down}
        Sleep, 20
        Send, {Esc}
        Sleep, 60
        Send, {Shift up}
        Sleep, 40
        Send, {Esc}
        ShowFloatText("Fight Mode ON")
    } else {
        SendInput, 1
        SendInput, 1
        SendInput, {LCtrl}
        SendInput, {Shift}
        ShowFloatText("Fight Mode OFF")
    }
} else if (currentGear = 2) {
    nightMode := !nightMode
    ShowFloatText("Night Mode " (nightMode ? "ON" : "OFF"))
    SendInput, % nightMode ? 5 : 2
} else if (currentGear = 3) {
    eating := !eating
    ShowFloatText("Auto-Eat " (eating ? "ON" : "OFF"))
    SetTimer, AutoEat, % eating ? 360000 : "Off"
    if (eating)
        Gosub, AutoEat
} else if (currentGear = 4) {
    pressingE := !pressingE
    ShowFloatText("E Spam " (pressingE ? "ON" : "OFF"))
    SetTimer, AutoE, % pressingE ? 50 : "Off"
} else if (currentGear = 5) {
    lumberMode := (lumberMode = 1 ? 2 : 1)
    ShowFloatText("Lumber Mode " lumberMode)
} else if (currentGear = 6) {
    ; Toggle very-fast left-click spam for Gear 6
    gear6Spamming := !gear6Spamming
    if (gear6Spamming) {
        ShowFloatText("Gear 6: Click Spam ON")
        ; Start spam timer at configured interval (5 ms)
        SetTimer, Gear6Spam, % gear6SpamInterval
    } else {
        ShowFloatText("Gear 6: Click Spam OFF")
        SetTimer, Gear6Spam, Off
    }
} else if (currentGear = 7) {
    ShowFloatText("Dancing (Gear 7)")
    danceCommand := danceList[danceIndex]
    SendInput, /
    Sleep, 100
    SendInput, /
    Sleep, 100
    SendInput, e
    Sleep, 100
    SendInput, {Enter}
    Sleep, 100
    SendInput, %danceCommand%
    Sleep, 100  ; <-- increased delay before Enter to avoid Enter firing too early
    SendInput, {Enter}
    Sleep, 100
    SendInput, {Enter}
}
return

; =====================================================
; Gear6 spam label
; runs at gear6SpamInterval ms while enabled
; =====================================================
Gear6Spam:
    global gear6Spamming, paused, currentGear
    ; safety checks: stop if paused or not in gear 6 or spamming disabled
    if (paused || !gear6Spamming || currentGear != 6) {
        SetTimer, Gear6Spam, Off
        return
    }
    ; perform a single left click
    Click
return

; =====================================================
; GEAR1 Sequence runner (wheeldown sequence non-blocking)
; - order: (on wheeldown) immediate: Send f
; - if sequence not already running, sequence runner will do:
;     Send 1
;     Sleep small gaps
;     Send f
;     SetTimer to call final send after 3000 ms which sends last 1 and backspace, then clears running flag
; - sequence will be aborted if gear1SeqRunning is cleared and the timers turned off
; =====================================================
Gear1Seq_Runner:
    global gear1SeqRunning
    ; protect: if flag unexpectedly false then exit
    if (gear1SeqRunning) {
        ; send the middle portion now (1, small gap, f) — this runs once at sequence start
        SendInput, 1
        Sleep, 30
        SendInput, f
        Sleep, 30
        ; schedule the final '1' + Backspace after 3000 ms (one-shot)
        SetTimer, Gear1Seq_Final, -3000
    }
return

Gear1Seq_Final:
    global gear1SeqRunning
    ; final step only runs if the timer fires — if aborted, the timer will have been turned off
    SendInput, 1
    Sleep, 8
    SendInput, {Backspace}
    gear1SeqRunning := false
return

; =====================================================
; SCROLL DOWN
; =====================================================
~WheelDown::
if (paused)
    return
if (currentGear = 1) {
    if (fightMode) {
        DoRangedShot()
        StartPotionCooldown(4.5)
    } else {
        ; always perform immediate first step 'f' so repeated WheelDowns still trigger it
        SendInput, f

        ; if the sequence is not already scheduled/running, start it
        if (!gear1SeqRunning) {
            gear1SeqRunning := true
            ; call runner shortly (non-blocking), runner will send 1,f and schedule final 1 after 3000ms
            SetTimer, Gear1Seq_Runner, -10
        }
        ; done — immediate 'f' executed; the rest of the sequence handled by timers
    }
} else if (currentGear = 4) {
    SendInput, 1
    SendInput, f
    SendInput, 1
} else if (currentGear = 5) {
    if (lumberMode = 1) {
        SendInput, 1
        SendInput, f
        SendInput, 4
    } else {
        SendInput, 1
        SendInput, e
        SendInput, f
        SendInput, 4
    }
} else if (currentGear = 7) {
    danceIndex++
    if (danceIndex > danceList.Length())
        danceIndex := 1
    displayDance := RegExReplace(danceList[danceIndex], "^/e\s*", "")
    StringUpper, displayDance, displayDance
    ShowFloatText(displayDance)
} else if (currentGear = 2) {
    if (nightMode) {
        SendInput, 1
        SendInput, f
        SendInput, 5
    } else {
        DoRangedShot()
    }
}
return

AutoEat:
if (paused || currentGear != 3 || !eating)
    return
IfWinExist, ahk_exe RobloxPlayerBeta.exe
{
    WinActivate
    WinWaitActive, ahk_exe RobloxPlayerBeta.exe, , 1
}
WinGetPos, wx, wy, ww, wh, ahk_exe RobloxPlayerBeta.exe
cx := wx + (ww // 2)
cy := wy + (wh // 2)
MouseMove, %cx%, %cy%, 0
SendInput, 9
Sleep, 60
Click
Sleep, 60
SendInput, 9
return

AutoE:
if (paused || currentGear != 4 || !pressingE)
    return
SendInput, e
return

~RButton::
if (paused)
    return
if (currentGear = 1 && fightMode) {
    ShowFloatText("⚔️ Fight Mode Alternate Hold")
    altHold := true
    holdDir := "A"
    SetTimer, FightHoldStrafe, 100
    return
}
return

~RButton up:: 
altHold := false
SetTimer, FightHoldStrafe, Off
SendInput, {a up}
SendInput, {d up}
return

FightHoldStrafe:
if (!altHold)
    return
if GetKeyState("a", "P") {
    SendInput, {d up}
    SendInput, {a down}
    holdDir := "A"
    return
}
if GetKeyState("d", "P") {
    SendInput, {a up}
    SendInput, {d down}
    holdDir := "D"
    return
}
if (holdDir = "A") {
    SendInput, {d up}
    SendInput, {a down}
    holdDir := "D"
} else {
    SendInput, {a up}
    SendInput, {d down}
    holdDir := "A"
}
return

; -----------------------
; Modified Q hotkey:
; - forward real 'q' when paused (chat mode) so typing q works
; - otherwise decide by focused control: send real 'q' if a control is focused, else send only 'm'
; -----------------------
*q::
    ; If paused (chat mode) forward real q immediately so you can type in chat.
    if (paused) {
        SendInput, q
        return
    }
    ; Check focused control in active window (Roblox). If non-empty, forward q so typing works.
    ControlGetFocus, focusedCtrl, A
    if (focusedCtrl != "") {
        SendInput, q
    } else {
        ; not in a focusable input - send only m (gameplay)
        SendInput, m
    }
return

~*q up::  ; keep keyup passthrough harmless (no action needed on release)
return

; =====================================================
; Push-to-talk (Left Alt)
; - on press edge: save mouse pos, move to 227,41, then move 1 pixel up, then click (fires once)
; - on release edge: run the click sequence, then restore mouse pos to saved coordinates,
;   then sleep postRestoreDelay ms, then move the pointer 1 pixel down (y+1) as requested
; - does NOT repeat while holding (edge-detected using lAltPressed)
; - uses screen coordinates (CoordMode, Mouse, Screen is set above)
; =====================================================
~LAlt::
    global lAltPressed, paused, prevMouseX, prevMouseY
    if (paused)
        return
    ; if already pressed (auto-repeat), ignore
    if (lAltPressed)
        return
    ; save current mouse position
    MouseGetPos, prevMouseX, prevMouseY
    lAltPressed := true
    MouseMove, 227, 41, 0
    Sleep, 8
    MouseMove, 227, 40, 0
    Sleep, 8
    Click
return

~LAlt up::
    global lAltPressed, paused, prevMouseX, prevMouseY, postRestoreDelay
    if (paused)
        return
    ; allow release sequence even if flag missing, but ensure flag cleared
    lAltPressed := false
    MouseMove, 227, 41, 0
    Sleep, 8
    MouseMove, 227, 40, 0
    Sleep, 8
    Click
    ; small delay to ensure click registers, then restore previous mouse pos
    Sleep, 8
    MouseMove, %prevMouseX%, %prevMouseY%, 0
    ; wait the requested post-restore delay then move pointer 1 pixel (y + 1)
    Sleep, %postRestoreDelay%
    tempY := prevMouseY + 1
    MouseMove, %prevMouseX%, %tempY%, 0
return

#IfWinActive
