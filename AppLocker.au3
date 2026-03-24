#include <Misc.au3>
#include <Crypt.au3>
#include <File.au3>
#include <GUIConstantsEx.au3>
#include <GuiListView.au3>
#include <MsgBoxConstants.au3>
#include <Process.au3>
#include <TrayConstants.au3>
#include <WindowsConstants.au3>
#include <GuiMenu.au3>

;— منع نسخة ثانية
If _Singleton("AppLockerInstance", 1) = 0 Then
    MsgBox($MB_ICONERROR, "Already Running", "An instance is already running.")
    Exit
EndIf

;— ثوابت
Global Const $INI_FILE      = @TempDir & "\Settings.ini"
Global Const $DEFAULT_HASH  = "ee106faf787ff81594ba16c2c3c726c0"
Global Const $STARTUP_KEY   = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
Global Const $APP_NAME      = "AppLocker"
Global Const $SECTION_BLOCK = "Blocked"
Global Const $SECTION_EXCEP = "Exceptions"
Global Const $INI_DEFAULT_EXCEP_TIME = "DefaultExceptionTime"
Global Const $SELF_NAME     = StringLower(@ScriptName)
Global Const $INTERP_NAME   = StringLower(@AutoItExe)
Opt("TrayMenuMode", 1)

;========================================
;— دوال مساعدة
;========================================
Func _ToHexString($bin)
    Local $hex = ""
    For $i = 1 To BinaryLen($bin)
        $hex &= Hex(BinaryMid($bin, $i, 1), 2)
    Next
    Return StringLower($hex)
EndFunc

Func _PromptPassword()
    Local $stored = IniRead($INI_FILE, "Settings", "Password", "")
    Local $p = InputBox("Password Required", "Enter password:", "", "*")
    If @error Or $p = "" Then Return False
    If _ToHexString(_Crypt_HashData($p, $CALG_MD5)) <> $stored Then
        MsgBox($MB_ICONERROR, "Access Denied", "Wrong password!")
        Return False
    EndIf
    Return True
EndFunc

;— تهيئة ملف الإعدادات أول مرة
If Not FileExists($INI_FILE) Then
    Local $m = InputBox("Access Recovery", "Settings file missing. Enter MASTER password:", "", "*")
    If @error Or $m = "" Then Exit
    If _ToHexString(_Crypt_HashData($m, $CALG_MD5)) <> $DEFAULT_HASH Then
        MsgBox($MB_ICONERROR, "Access Denied", "Incorrect master password.")
        Exit
    EndIf
    Local $new = InputBox("Set New Password", "Enter new password:", "", "*")
    If @error Or $new = "" Then Exit
    FileWrite($INI_FILE, "[Blocked]" & @CRLF & "[Exceptions]" & @CRLF & "[Settings]" & @CRLF)
    IniWrite($INI_FILE, "Settings", "Password", _ToHexString(_Crypt_HashData($new, $CALG_MD5)))
    IniWrite($INI_FILE, "Settings", $INI_DEFAULT_EXCEP_TIME, "30") ; Set default exception time
    MsgBox($MB_ICONINFORMATION, "Setup Complete", "Password set successfully.")
EndIf

;========================================
;— إنشاء الواجهة (مخفية أولًا)
;========================================
Local $hGUI = GUICreate("AppLocker", 500, 520)
GUISetState(@SW_HIDE, $hGUI)

;— شريط القوائم
Local $hMenuFile        = GUICtrlCreateMenu("File")
Local $hMenuSettings    = GUICtrlCreateMenuItem("Settings",       $hMenuFile)
Local $hMenuControls    = GUICtrlCreateMenu("Controls")
Local $hMenuBlockApps   = GUICtrlCreateMenuItem("Block Applications", $hMenuControls)
Local $hMenuBlockFiles  = GUICtrlCreateMenuItem("Block Files",        $hMenuControls)
Local $hMenuHideFiles   = GUICtrlCreateMenuItem("Hide Files",         $hMenuControls)
Local $hMenuHideFolders = GUICtrlCreateMenuItem("Hide Folders",       $hMenuControls)
Local $hMenuHelp        = GUICtrlCreateMenu("Help")
Local $hMenuAbout       = GUICtrlCreateMenuItem("About",              $hMenuHelp)

;========================================
;— صفحة Settings
;========================================
Local $hLabelSettings    = GUICtrlCreateLabel("Settings",            10, 20, 150, 20)
Local $btnChangePassword = GUICtrlCreateButton("Change Password…",   10, 50, 150, 30)
Local $btnAutoStartWin   = GUICtrlCreateButton("Run at Startup: Off",10, 90, 150, 30)
Local $hLabelDefaultExcep = GUICtrlCreateLabel("Default Exception (mins):", 10, 130, 150, 20)
Local $hInputDefaultExcep = GUICtrlCreateInput("30", 170, 130, 50, 20)
Local $btnSaveDefaultExcep = GUICtrlCreateButton("Save Default Exception", 10, 160, 150, 30)
Local $btnSettingsClose  = GUICtrlCreateButton("X",                  470,10, 20, 20)
Global $aSettingsControls = [ _
    $hLabelSettings, $btnChangePassword, $btnAutoStartWin, $btnSettingsClose, _
    $hLabelDefaultExcep, $hInputDefaultExcep, $btnSaveDefaultExcep _
]

;========================================
;— صفحة Block Applications
;========================================
Local $hLabelApps    = GUICtrlCreateLabel("Blocked Applications:",10, 20, 150, 20)
Global $hList        = GUICtrlCreateListView( _
                          "Application Name|Blocked", 10, 40, 300, 269, _
                          BitOR($WS_BORDER, $LVS_REPORT, $LVS_SHOWSELALWAYS), _
                          $LVS_EX_CHECKBOXES)
Global $hStatus      = GUICtrlCreateLabel("",                        320, 20, 150, 20)
Local $btnAddApp     = GUICtrlCreateButton("Add Application…",      320, 40, 150, 30)
Local $btnRemApp     = GUICtrlCreateButton("Remove Application…",   320, 80, 150, 30)
Local $btnBlockSel   = GUICtrlCreateButton("Block Selected…",        320,120,150,30)
Local $btnUnblock    = GUICtrlCreateButton("Unblock Selected…",      320,160,150,30)
Local $btnSetEx      = GUICtrlCreateButton("Set Exception…",         320,200,150,30)
Local $btnStartup    = GUICtrlCreateButton("Run at Startup: Off",    320,240,150,30)
Local $btnRemEx      = GUICtrlCreateButton("Remove Exception…",       320,280,150,30)
Local $btnCloseApp   = GUICtrlCreateButton("X",                      470,10, 20, 20)
Local $hLabelEx      = GUICtrlCreateLabel("Scheduled Exceptions:",  10,340,250,20)
Global $hSched       = GUICtrlCreateListView( _
                          "Application|Start Date|Start Time|End Date|End Time", _
                          10,360,480,120, _
                          BitOR($WS_BORDER, $LVS_REPORT), $LVS_EX_FULLROWSELECT)
_GUICtrlListView_SetColumnWidth($hSched, 0, 180)
_GUICtrlListView_SetColumnWidth($hSched, 1,  80)
_GUICtrlListView_SetColumnWidth($hSched, 2,  70)
_GUICtrlListView_SetColumnWidth($hSched, 3,  80)
_GUICtrlListView_SetColumnWidth($hSched, 4,  70)

Global $aBlockAppControls = [ _
    $hLabelApps, $hList, $hStatus, _
    $btnAddApp, $btnRemApp, $btnBlockSel, $btnUnblock, _
    $btnSetEx, $btnStartup, $btnRemEx, $btnCloseApp, _
    $hLabelEx, $hSched _
]

;— أيقونات التري
Local $idShow = TrayCreateItem("Show Control Panel")
Local $idExit  = TrayCreateItem("Exit")
TraySetState($TRAY_ICONSTATE_SHOW)

;— سجل مراقبة الحظر
AdlibRegister("_MonitorBlocked", 1000)
_LoadSettings()
_LoadList()

;========================================
;— دوال إظهار/إخفاء الصفحات
;========================================
Func _ShowSettings()
    For $h In $aSettingsControls
        GUICtrlSetState($h, $GUI_SHOW)
    Next
EndFunc

Func _HideSettings()
    For $h In $aSettingsControls
        GUICtrlSetState($h, $GUI_HIDE)
    Next
EndFunc

Func _ShowBlockApps()
    For $h In $aBlockAppControls
        GUICtrlSetState($h, $GUI_SHOW)
    Next
EndFunc

Func _HideBlockApps()
    For $h In $aBlockAppControls
        GUICtrlSetState($h, $GUI_HIDE)
    Next
EndFunc

;========================================
;— الحلقة الرئيسية للأحداث
;========================================
While True
    Local $msg = GUIGetMsg()

    Switch $msg
        ;— عندما يضغط المستخدم على زر Minimize
        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)
            ContinueLoop

        ; File → Settings
        Case $hMenuSettings
            _HideBlockApps()
            _LoadSettings()
            _ShowSettings()
            GUISetState(@SW_SHOW, $hGUI)

        ; Controls → Block Applications
        Case $hMenuBlockApps
            _HideSettings()
            _LoadList()
            _ShowBlockApps()
            GUISetState(@SW_SHOW, $hGUI)

        ; Other menu items
        Case $hMenuBlockFiles
            _HideSettings()
            _HideBlockApps()

        Case $hMenuHideFiles
            _HideSettings()
            _HideBlockApps()

        Case $hMenuHideFolders
            _HideSettings()
            _HideBlockApps()

        Case $hMenuAbout
            _HideSettings()
            _HideBlockApps()
            MsgBox($MB_ICONINFORMATION, "About", "AppLocker v1.0" & @CRLF & "© 2025")

        ;— Settings page buttons
        Case $btnChangePassword
            _ChangePassword()

        Case $btnAutoStartWin
            _ToggleStartup()

        Case $btnSettingsClose
            _HideSettings()

        Case $btnSaveDefaultExcep
            _SaveDefaultExceptionTime()

        ;— Block Applications page buttons
        Case $btnAddApp
            _AddProgram()

        Case $btnRemApp
            _RemoveProgram()

        Case $btnBlockSel
            _ToggleBlock(1)

        Case $btnUnblock
            _ToggleBlock(0)

        Case $btnSetEx
            _ScheduleException()

        Case $btnStartup
            _ToggleStartup()

        Case $btnRemEx
            _RemoveException()

        Case $btnCloseApp
            _HideBlockApps()

        ;— إغلاق النافذة
        Case $GUI_EVENT_CLOSE
            If _PromptPassword() Then ExitLoop
    EndSwitch

    ; Tray messages
    Local $t = TrayGetMsg()
    Switch $t
        Case $idShow
            If _PromptPassword() Then
                _HideSettings()
                _HideBlockApps()
                GUISetState(@SW_SHOW, $hGUI)
            EndIf
        Case $idExit
            If _PromptPassword() Then ExitLoop
    EndSwitch
WEnd

Exit

;========================================
;— دوال القائمة والجدولة والحظر
;========================================
Func _LoadSettings()
    Local $defaultTime = IniRead($INI_FILE, "Settings", $INI_DEFAULT_EXCEP_TIME, "30")
    GUICtrlSetData($hInputDefaultExcep, $defaultTime)
EndFunc

Func _LoadList()
    _GUICtrlListView_DeleteAllItems($hList)
    Local $cnt = 0
    Local $a = IniReadSection($INI_FILE, $SECTION_BLOCK)
    If @error Then Return
    For $i = 1 To $a[0][0]
        Local $pr = $a[$i][0]
        Local $v  = $a[$i][1]
        If StringLower($pr) = $SELF_NAME Or StringLower($pr) = $INTERP_NAME Then ContinueLoop
        Local $idx = GUICtrlCreateListViewItem($pr & "|" & ($v = "1" ? "Yes" : "No"), $hList)
        _GUICtrlListView_SetItemChecked($hList, $idx, $v = "1")
        If $v = "1" Then $cnt += 1
    Next
    GUICtrlSetData($hStatus, "Blocked Applications: " & $cnt)
    _LoadExceptions()
EndFunc

Func _LoadExceptions()
    _GUICtrlListView_DeleteAllItems($hSched)
    Local $e = IniReadSection($INI_FILE, $SECTION_EXCEP)
    If @error Then Return
    For $i = 1 To $e[0][0]
        Local $pr  = $e[$i][0]
        Local $val = $e[$i][1]
        Local $p   = StringSplit($val, "|")
        If $p[0] = 4 Then
            GUICtrlCreateListViewItem($pr & "|" & $p[1] & "|" & $p[2] & "|" & $p[3] & "|" & $p[4], $hSched)
        EndIf
    Next
EndFunc

Func _AddProgram()
    Local $p = InputBox("Add Application…", "Process name (e.g. chrome.exe):")
    If @error Or StringStripWS($p, 8) = "" Then Return
    If StringLower($p) = $SELF_NAME Or StringLower($p) = $INTERP_NAME Then
        MsgBox($MB_ICONWARNING, "Error", "Cannot block itself.")
        Return
    EndIf
    IniWrite($INI_FILE, $SECTION_BLOCK, $p, 0)
    _LoadList()
EndFunc

Func _RemoveProgram()
    For $i = _GUICtrlListView_GetItemCount($hList) - 1 To 0 Step -1
        If _GUICtrlListView_GetItemChecked($hList, $i) Then
            Local $pr = _GUICtrlListView_GetItemText($hList, $i, 0)
            IniDelete($INI_FILE, $SECTION_BLOCK, $pr)
            IniDelete($INI_FILE, $SECTION_EXCEP, $pr)
        EndIf
    Next
    _LoadList()
EndFunc

Func _ToggleBlock($state)
    For $i = 0 To _GUICtrlListView_GetItemCount($hList) - 1
        If _GUICtrlListView_GetItemChecked($hList, $i) Then
            Local $pr = _GUICtrlListView_GetItemText($hList, $i, 0)
            IniWrite($INI_FILE, $SECTION_BLOCK, $pr, $state)
        EndIf
    Next
    Sleep(100)
    _LoadList()
EndFunc

Func _ChangePassword()
    Local $p = InputBox("Change Password", "New password:", "", "*")
    If @error Or $p = "" Then Return
    IniWrite($INI_FILE, "Settings", "Password", _ToHexString(_Crypt_HashData($p, $CALG_MD5)))
    MsgBox($MB_ICONINFORMATION, "Settings", "Password updated.")
EndFunc

Func _ToggleStartup()
    Local $reg = RegRead($STARTUP_KEY, $APP_NAME)
    If @error Or $reg <> @ScriptFullPath Then
        RegWrite($STARTUP_KEY, $APP_NAME, "REG_SZ", @ScriptFullPath)
        GUICtrlSetData($btnStartup,    "Run at Startup: On")
        GUICtrlSetData($btnAutoStartWin,"Run at Startup: On")
        MsgBox($MB_ICONINFORMATION, "Settings", "Startup enabled.")
    Else
        RegDelete($STARTUP_KEY, $APP_NAME)
        GUICtrlSetData($btnStartup,    "Run at Startup: Off")
        GUICtrlSetData($btnAutoStartWin,"Run at Startup: Off")
        MsgBox($MB_ICONINFORMATION, "Settings", "Startup disabled.")
    EndIf
EndFunc

Func _ScheduleException()
    Local $d1 = @YEAR & "-" & StringFormat("%02d", @MON) & "-" & StringFormat("%02d", @MDAY)
    Local $t1 = StringFormat("%02d:%02d", @HOUR, @MIN)
    Local $defaultExcepTime = IniRead($INI_FILE, "Settings", $INI_DEFAULT_EXCEP_TIME, "30")
    Local $sum = @HOUR * 60 + @MIN + $defaultExcepTime
    Local $t2h = Mod(Int($sum / 60), 24)
    Local $t2m = Mod($sum, 60)
    Local $d2 = $d1
    Local $t2 = StringFormat("%02d:%02d", $t2h, $t2m)

    Local $hDlg = GUICreate("Set Exception…", 430, 180, -1, -1)
    GUISetFont(10, 400)
    GUICtrlCreateLabel("Start Date:", 10,  10, 140, 20)
    Local $hD1 = GUICtrlCreateInput($d1, 155, 10, 120, 20)
    GUICtrlCreateLabel("Start Time:", 285, 10, 100, 20)
    Local $hT1 = GUICtrlCreateInput($t1, 365, 10, 60, 20)
    GUICtrlCreateLabel("End Date:",   10,  50, 140, 20)
    Local $hD2 = GUICtrlCreateInput($d2, 155, 50, 120, 20)
    GUICtrlCreateLabel("End Time:",   285, 50, 100, 20)
    Local $hT2 = GUICtrlCreateInput($t2, 365, 50, 60, 20)
    Local $bOK = GUICtrlCreateButton("OK",     125, 100, 80, 30)
    Local $bC  = GUICtrlCreateButton("Cancel", 245, 100, 80, 30)
    GUISetState(@SW_SHOW)

    While True
        Local $m = GUIGetMsg()
        If $m = $bOK Then
            Local $sd = GUICtrlRead($hD1)
            Local $st = GUICtrlRead($hT1)
            Local $ed = GUICtrlRead($hD2)
            Local $et = GUICtrlRead($hT2)
            If Not StringRegExp($sd, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($st, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            If Not StringRegExp($ed, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($et, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            GUIDelete($hDlg)
            For $i = 0 To _GUICtrlListView_GetItemCount($hList) - 1
                If _GUICtrlListView_GetItemChecked($hList, $i) Then
                    Local $pr = _GUICtrlListView_GetItemText($hList, $i, 0)
                    IniWrite($INI_FILE, $SECTION_EXCEP, $pr, $sd & "|" & $st & "|" & $ed & "|" & $et)
                EndIf
            Next
            MsgBox($MB_ICONINFORMATION, "Block Applications", _
                "Exception scheduled from " & $sd & " " & $st & @CRLF & "to " & $ed & " " & $et)
            _LoadList()
            Return
        ElseIf $m = $bC Or $m = $GUI_EVENT_CLOSE Then
            GUIDelete($hDlg)
            Return
        EndIf
    WEnd
EndFunc

Func _RemoveException()
    For $i = _GUICtrlListView_GetItemCount($hSched) - 1 To 0 Step -1
        If _GUICtrlListView_GetItemSelected($hSched, $i) Then
            Local $pr = _GUICtrlListView_GetItemText($hSched, $i, 0)
            IniDelete($INI_FILE, $SECTION_EXCEP, $pr)
        EndIf
    Next
    _LoadList()
EndFunc

Func _SaveDefaultExceptionTime()
    Local $newDefaultTime = GUICtrlRead($hInputDefaultExcep)
    ; AutoIt reads Input controls as strings, so we use StringIsInt and check the value
    If Not StringIsInt($newDefaultTime) Or Number($newDefaultTime) <= 0 Then
        MsgBox($MB_ICONERROR, "Error", "Please enter a valid positive number for default exception time.")
        Return
    EndIf
    IniWrite($INI_FILE, "Settings", $INI_DEFAULT_EXCEP_TIME, Number($newDefaultTime))
    MsgBox($MB_ICONINFORMATION, "Settings", "Default exception time updated.")
EndFunc

Func _MonitorBlocked()
    Local $a = IniReadSection($INI_FILE, $SECTION_BLOCK)
    If @error Then Return
    Local $now = @YEAR & "-" & StringFormat("%02d", @MON) & "-" & StringFormat("%02d", @MDAY) & _
                  " " & StringFormat("%02d", @HOUR) & ":" & StringFormat("%02d", @MIN)
    For $i = 1 To $a[0][0]
        If $a[$i][1] = "1" Then
            Local $pr  = $a[$i][0]
            Local $exc = IniRead($INI_FILE, $SECTION_EXCEP, $pr, "")
            Local $p   = StringSplit($exc, "|")
            Local $skip = False
            If IsArray($p) And $p[0] = 4 Then
                Local $s = $p[1] & " " & $p[2]
                Local $e = $p[3] & " " & $p[4]
                If $now >= $s And $now < $e Then
                    $skip = True
                ElseIf $now >= $e Then
                    IniDelete($INI_FILE, $SECTION_EXCEP, $pr)
                EndIf
            EndIf
            If Not $skip And ProcessExists($pr) Then
                ProcessClose($pr)
            EndIf
        EndIf
    Next
EndFunc
