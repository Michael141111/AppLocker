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
#include <WinAPI.au3>


;— منع نسخة ثانية
If _Singleton("AppLockerInstance", 1) = 0 Then
    MsgBox($MB_ICONERROR, "Already Running", "An instance is already running.")
    Exit
EndIf

;— ثوابت
Global Const $SECTION_FILE_PATHS = "FilePaths"
Global Const $SECTION_FILE_STATE = "BlockedFiles"
Global $g_hFileHandles = ObjCreate("Scripting.Dictionary")
Global Const $INI_FILE            = @TempDir & "\Settings.ini"
Global Const $DEFAULT_HASH        = "ee106faf787ff81594ba16c2c3c726c0"
Global Const $STARTUP_KEY         = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
Global Const $APP_NAME            = "AppLocker"
Global Const $SECTION_BLOCK       = "Blocked"
Global Const $SECTION_EXCEP       = "Exceptions"
Global Const $SECTION_FILE_BLOCK  = "BlockedFiles"
Global Const $SECTION_FILE_EXCEP  = "ExceptionsFiles"
Global Const $SELF_NAME           = StringLower(@ScriptName)
Global Const $INTERP_NAME         = StringLower(@AutoItExe)
Opt("TrayMenuMode", 1)

;— دوال مساعدة
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
    FileWrite($INI_FILE, _
      "[Blocked]"          & @CRLF & _
      "[Exceptions]"       & @CRLF & _
      "[BlockedFiles]"     & @CRLF & _
      "[ExceptionsFiles]"  & @CRLF & _
      "[Settings]"         & @CRLF)
    IniWrite($INI_FILE, "Settings", "Password", _ToHexString(_Crypt_HashData($new, $CALG_MD5)))
    MsgBox($MB_ICONINFORMATION, "Setup Complete", "Password set successfully.")
EndIf

;— إنشاء الواجهة (مخفية أولًا)
Local $hGUI = GUICreate("AppLocker", 700, 520)
GUISetState(@SW_HIDE, $hGUI)


;— شريط القوائم
Local $hMenuFile        = GUICtrlCreateMenu("File")
Local $hMenuSettings    = GUICtrlCreateMenuItem("Settings", $hMenuFile)
Local $hMenuControls    = GUICtrlCreateMenu("Controls")
Local $hMenuBlockApps   = GUICtrlCreateMenuItem("Block Applications", $hMenuControls)
Local $hMenuBlockFiles  = GUICtrlCreateMenuItem("Block Files",        $hMenuControls)
Local $hMenuHideFiles   = GUICtrlCreateMenuItem("Hide Files",         $hMenuControls)
Local $hMenuHideFolders = GUICtrlCreateMenuItem("Hide Folders",       $hMenuControls)
Local $hMenuHelp        = GUICtrlCreateMenu("Help")
Local $hMenuAbout       = GUICtrlCreateMenuItem("About", $hMenuHelp)

;— صفحة Settings
Local $hLabelSettings    = GUICtrlCreateLabel("Settings",          10, 20, 150, 20)
Local $btnChangePassword = GUICtrlCreateButton("Change Password…", 10, 50, 150, 30)
Local $btnAutoStartWin   = GUICtrlCreateButton("Run at Startup: Off",10, 90, 150, 30)
Local $btnSettingsClose  = GUICtrlCreateButton("X",                670,10,20,20)
Global $aSettingsControls = [ _
    $hLabelSettings, $btnChangePassword, $btnAutoStartWin, $btnSettingsClose _
]

;— صفحة Block Applications
Local $hLabelApps  = GUICtrlCreateLabel("Blocked Applications:",10, 20, 150,20)
Global $hList      = GUICtrlCreateListView( _
    "Application Name|Blocked", _
    10,40,300,270, _
    BitOR($WS_BORDER,$LVS_REPORT,$LVS_SHOWSELALWAYS), _
    $LVS_EX_CHECKBOXES)
Global $hStatus    = GUICtrlCreateLabel("",320,20,150,20)
Local $btnAddApp   = GUICtrlCreateButton("Add Application…",   320,40,150,30)
Local $btnRemApp   = GUICtrlCreateButton("Remove Application…",320,80,150,30)
Local $btnBlockSel = GUICtrlCreateButton("Block Selected…",     320,120,150,30)
Local $btnUnblock  = GUICtrlCreateButton("Unblock Selected…",   320,160,150,30)
Local $btnSetEx    = GUICtrlCreateButton("Set Exception…",      320,200,150,30)
Local $btnRemEx    = GUICtrlCreateButton("Remove Exception…",   320,240,150,30)
Local $btnCloseApp = GUICtrlCreateButton("X",                   670,10,20,20)
Local $hLabelEx    = GUICtrlCreateLabel("Scheduled Exceptions:",10,340,250,20)
Global $hSched = GUICtrlCreateListView( _
    "Application|Start Date|Start Time|End Date|End Time", _
    10, 360, 680, 120, _
    BitOR($WS_BORDER, $LVS_REPORT), _
    $LVS_EX_FULLROWSELECT _
)
_GUICtrlListView_SetColumnWidth($hSched,0,200)
_GUICtrlListView_SetColumnWidth($hSched,1,100)
_GUICtrlListView_SetColumnWidth($hSched,2, 90)
_GUICtrlListView_SetColumnWidth($hSched,3,100)
_GUICtrlListView_SetColumnWidth($hSched,4, 90)

Global $aBlockAppControls = [ _
    $hLabelApps, $hList, $hStatus, _
    $btnAddApp, $btnRemApp, $btnBlockSel, $btnUnblock, _
    $btnSetEx, $btnRemEx, $btnCloseApp, $hLabelEx, $hSched _
]
;— صفحة Block Files
Local $hLabelFiles    = GUICtrlCreateLabel("Blocked Files:",      10, 20,150,20)
Global $hListFiles    = GUICtrlCreateListView( _
    "File Name|Full Path|Blocked", _
    10,40,300,270, _
    BitOR($WS_BORDER,$LVS_REPORT,$LVS_SHOWSELALWAYS), _
    $LVS_EX_CHECKBOXES)
Global $hStatusFiles  = GUICtrlCreateLabel("",                   320,20,150,20)
Local $btnAddFile     = GUICtrlCreateButton("Add File…",           320,40,150,30)
Local $btnRemFile     = GUICtrlCreateButton("Remove File…",        320,80,150,30)
Local $btnBlockSelFile= GUICtrlCreateButton("Block Selected…",     320,120,150,30)
Local $btnUnblockFile = GUICtrlCreateButton("Unblock Selected…",   320,160,150,30)
Local $btnSetFileEx   = GUICtrlCreateButton("Set Exception…",      320,200,150,30)
Local $btnRemFileEx   = GUICtrlCreateButton("Remove Exception…",   320,240,150,30)
Local $btnCloseFile   = GUICtrlCreateButton("X",                   670,10,20,20)
Local $hLabelFileEx   = GUICtrlCreateLabel("Scheduled Exceptions:",10,340,250,20)
Global $hSchedFiles   = GUICtrlCreateListView( _
    "File|Start Date|Start Time|End Date|End Time", _
    10,360,680,120, _
    BitOR($WS_BORDER,$LVS_REPORT), _
    $LVS_EX_FULLROWSELECT)
_GUICtrlListView_SetColumnWidth($hSchedFiles,0,200)
_GUICtrlListView_SetColumnWidth($hSchedFiles,1,100)
_GUICtrlListView_SetColumnWidth($hSchedFiles,2, 90)
_GUICtrlListView_SetColumnWidth($hSchedFiles,3,100)
_GUICtrlListView_SetColumnWidth($hSchedFiles,4, 90)

Global $aBlockFileControls = [ _
    $hLabelFiles, $hListFiles, $hStatusFiles, _
    $btnAddFile, $btnRemFile, $btnBlockSelFile, $btnUnblockFile, _
    $btnSetFileEx, $btnRemFileEx, $btnCloseFile, $hLabelFileEx, $hSchedFiles _
]


_HideSettings()
_HideBlockApps()
_HideBlockFiles()


;— أيقونات التري
Local $idShow = TrayCreateItem("Show Control Panel")
Local $idExit = TrayCreateItem("Exit")
TraySetState($TRAY_ICONSTATE_SHOW)

;— سجل مراقبة الحظر
AdlibRegister("_MonitorBlocked", 1000)

_LoadList()       ; لملء قائمة التطبيقات أولاً
_LoadFileList()   ; لملء قائمة الملفات إذا أردت


;— دوال إظهار/إخفاء الصفحات
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

Func _ShowBlockFiles()
    For $h In $aBlockFileControls
        GUICtrlSetState($h, $GUI_SHOW)
    Next
EndFunc

Func _HideBlockFiles()
    For $h In $aBlockFileControls
        GUICtrlSetState($h, $GUI_HIDE)
    Next
EndFunc

;— إضافة ملف
Func _AddFile()
    ; 1) اختر ملف
Local $sFile = FileOpenDialog( _
    "Select File to Block", _
    @ScriptDir, _
    "All files (*.*)", _
    $FD_FILEMUSTEXIST)
    
    If @error Or $sFile = "" Then Return

    ; 2) استخرج اسم الملف فقط (بدون المسار)
    Local $sName = StringTrimLeft($sFile, StringInStr($sFile, "\", 0, -1))

    ; 3) سجّل الاسم والمسار في الـ INI (حالة الحظر الافتراضية = 0)
   IniWrite($INI_FILE, $SECTION_FILE_PATHS, $sName, $sFile)
IniWrite($INI_FILE, $SECTION_FILE_STATE, $sName, 0)


    ; 4) أعد تحميل القائمة لإظهار التغيير
    _LoadFileList()
EndFunc




;— الحلقة الرئيسية للأحداث
While True
    Local $msg = GUIGetMsg()
    Switch $msg
        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)

        Case $hMenuSettings
            _HideBlockApps()
            _HideBlockFiles()
            _ShowSettings()
            GUISetState(@SW_SHOW, $hGUI)

        Case $hMenuBlockApps
            _HideSettings()
            _HideBlockFiles()
            _LoadList()
            _ShowBlockApps()
            GUISetState(@SW_SHOW, $hGUI)

        Case $hMenuBlockFiles
            _HideSettings()
            _HideBlockApps()
            _LoadFileList()
            _ShowBlockFiles()
            GUISetState(@SW_SHOW, $hGUI)

        Case $hMenuHideFiles, $hMenuHideFolders
            _HideSettings()
            _HideBlockApps()
            _HideBlockFiles()

        Case $hMenuAbout
            _HideSettings()
            _HideBlockApps()
            _HideBlockFiles()
            MsgBox($MB_ICONINFORMATION, "About", "AppLocker v1.0" & @CRLF & "© 2025")

        ;— Settings
        Case $btnChangePassword
            _ChangePassword()
        Case $btnAutoStartWin
            _ToggleStartup()
        Case $btnSettingsClose
            _HideSettings()

        ;— Block Applications
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
        Case $btnRemEx
            _RemoveException()
        Case $btnCloseApp
            _HideBlockApps()

        ;— Block Files
        Case $btnAddFile
            _AddFile()
        Case $btnRemFile
            _RemoveFile()
        Case $btnBlockSelFile
            _ToggleBlockFile(1)
        Case $btnUnblockFile
            _ToggleBlockFile(0)
        Case $btnSetFileEx
            _ScheduleFileException()
        Case $btnRemFileEx
            _RemoveFileException()
        Case $btnCloseFile
            _HideBlockFiles()

        Case $GUI_EVENT_CLOSE
            If _PromptPassword() Then ExitLoop
    EndSwitch

    ;— رسائل التري
    Local $t = TrayGetMsg()
    If $t = $idShow And _PromptPassword() Then
        GUISetState(@SW_SHOW, $hGUI)
    EndIf
    If $t = $idExit And _PromptPassword() Then
        ExitLoop
    EndIf
WEnd

;— نخرج من البرنامج
Exit
;— تحميل قائمة التطبيقات المحظورة وحالة الحظر
Func _LoadList()
    _GUICtrlListView_DeleteAllItems($hList)
    Local $cnt = 0
    Local $a = IniReadSection($INI_FILE, $SECTION_BLOCK)
    If @error Then Return

    For $i = 1 To $a[0][0]
        Local $pr = $a[$i][0], $v = $a[$i][1]
        If StringLower($pr) = $SELF_NAME Or StringLower($pr) = $INTERP_NAME Then ContinueLoop
        Local $idx = GUICtrlCreateListViewItem($pr & "|" & ($v = "1" ? "Yes" : "No"), $hList)
        _GUICtrlListView_SetItemChecked($hList, $idx, $v = "1")
        If $v = "1" Then $cnt += 1
    Next

    GUICtrlSetData($hStatus, "Blocked Applications: " & $cnt)
    _LoadExceptions()
EndFunc

;— استثناءات التطبيقات المجدولة
Func _LoadExceptions()
    _GUICtrlListView_DeleteAllItems($hSched)
    Local $e = IniReadSection($INI_FILE, $SECTION_EXCEP)
    If @error Then Return

    For $i = 1 To $e[0][0]
        Local $nm = $e[$i][0], $v = $e[$i][1]
        Local $p = StringSplit($v, "|")
        If UBound($p) = 5 Then
            GUICtrlCreateListViewItem($nm & "|" & $p[1] & "|" & $p[2] & "|" & $p[3] & "|" & $p[4], $hSched)
        EndIf
    Next
EndFunc

;— إضافة تطبيق جديد
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

;— إزالة تطبيق
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

;— تبديل حالة الحظر
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

;— تغيير كلمة المرور
Func _ChangePassword()
    Local $p = InputBox("Change Password", "New password:", "", "*")
    If @error Or $p = "" Then Return
    IniWrite($INI_FILE, "Settings", "Password", _ToHexString(_Crypt_HashData($p, $CALG_MD5)))
    MsgBox($MB_ICONINFORMATION, "Settings", "Password updated.")
EndFunc

;— تشغيل/إيقاف التشغيل مع بدء الويندوز
Func _ToggleStartup()
    Local $reg = RegRead($STARTUP_KEY, $APP_NAME)
    If @error Or $reg <> @ScriptFullPath Then
        RegWrite($STARTUP_KEY, $APP_NAME, "REG_SZ", @ScriptFullPath)
        GUICtrlSetData($btnAutoStartWin, "Run at Startup: On")
        MsgBox($MB_ICONINFORMATION, "Settings", "Startup enabled.")
    Else
        RegDelete($STARTUP_KEY, $APP_NAME)
        GUICtrlSetData($btnAutoStartWin, "Run at Startup: Off")
        MsgBox($MB_ICONINFORMATION, "Settings", "Startup disabled.")
    EndIf
EndFunc

;— جدولة استثناء للتطبيقات
Func _ScheduleException()
    Local $d1 = @YEAR & "-" & StringFormat("%02d", @MON) & "-" & StringFormat("%02d", @MDAY)
    Local $t1 = StringFormat("%02d:%02d", @HOUR, @MIN)
    Local $sum = @HOUR * 60 + @MIN + 30
    Local $t2h = Mod(Int($sum / 60), 24), $t2m = Mod($sum, 60)
    Local $d2 = $d1, $t2 = StringFormat("%02d:%02d", $t2h, $t2m)

    Local $hDlg = GUICreate("Set Exception…", 430, 180, -1, -1)
    GUISetFont(10, 400)
    GUICtrlCreateLabel("Start Date:", 10, 10, 140, 20)
    Local $hD1 = GUICtrlCreateInput($d1, 155, 10, 120, 20)
    GUICtrlCreateLabel("Start Time:", 285, 10, 100, 20)
    Local $hT1 = GUICtrlCreateInput($t1, 365, 10, 60, 20)
    GUICtrlCreateLabel("End Date:",   10, 50, 140, 20)
    Local $hD2 = GUICtrlCreateInput($d2, 155, 50, 120, 20)
    GUICtrlCreateLabel("End Time:",   285, 50, 100, 20)
    Local $hT2 = GUICtrlCreateInput($t2, 365, 50, 60, 20)
    Local $bOK = GUICtrlCreateButton("OK", 125, 100, 80, 30)
    Local $bC  = GUICtrlCreateButton("Cancel", 245, 100, 80, 30)
    GUISetState(@SW_SHOW)

    While True
        Local $msg = GUIGetMsg()

    ; Keyboard navigation using Enter
    If _IsPressed("0D") Then ; Enter key
        If ControlGetFocus($hDlg) = "Edit1" Then
            GUICtrlSetState($hT1, $GUI_FOCUS)
        ElseIf ControlGetFocus($hDlg) = "Edit2" Then
            GUICtrlSetState($hD2, $GUI_FOCUS)
        ElseIf ControlGetFocus($hDlg) = "Edit3" Then
            GUICtrlSetState($hT2, $GUI_FOCUS)
        ElseIf ControlGetFocus($hDlg) = "Edit4" Then
            GUICtrlSetState($bOK, $GUI_FOCUS)
        EndIf
        Sleep(150) ; prevent multiple triggers
    EndIf

        If $msg = $bOK Then
            Local $sd = GUICtrlRead($hD1), $st = GUICtrlRead($hT1)
            Local $ed = GUICtrlRead($hD2), $et = GUICtrlRead($hT2)
            If Not StringRegExp($sd, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($st, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            If Not StringRegExp($ed, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($et, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            GUIDelete($hDlg)

            ;— سجل الاستثناء لكل تطبيق محدد
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
        ElseIf $msg = $bC Or $msg = $GUI_EVENT_CLOSE Then
            GUIDelete($hDlg)
            Return
        EndIf
    WEnd
EndFunc

;— إزالة استثناء
Func _RemoveException()
    For $i = _GUICtrlListView_GetItemCount($hSched) - 1 To 0 Step -1
        If _GUICtrlListView_GetItemSelected($hSched, $i) Then
            Local $pr = _GUICtrlListView_GetItemText($hSched, $i, 0)
            IniDelete($INI_FILE, $SECTION_EXCEP, $pr)
        EndIf
    Next
    _LoadList()
EndFunc
;— قاموس مقابض الملفات المغلقة
Global $g_hFileHandles = ObjCreate("Scripting.Dictionary")

;— تحميل استثناءات الملفات
Func _LoadFileExceptions()
    _GUICtrlListView_DeleteAllItems($hSchedFiles)
    Local $e = IniReadSection($INI_FILE, $SECTION_FILE_EXCEP)
    If @error Then Return

    For $i = 1 To $e[0][0]
        Local $nm = $e[$i][0], $v = $e[$i][1]
        Local $p = StringSplit($v, "|")
        If UBound($p) = 5 Then
            GUICtrlCreateListViewItem($nm & "|" & $p[1] & "|" & $p[2] & "|" & $p[3] & "|" & $p[4], $hSchedFiles)
        EndIf
    Next
EndFunc

;— تحميل قائمة الملفات وحالة الحظر
Func _LoadFileList()
    _GUICtrlListView_DeleteAllItems($hListFiles)
    Local $cnt = 0
    Local $a = IniReadSection($INI_FILE, $SECTION_FILE_PATHS)
    If @error Then Return

    For $i = 1 To $a[0][0]
        Local $nm   = $a[$i][0]
        Local $path = $a[$i][1]
        Local $st   = IniRead($INI_FILE, $SECTION_FILE_STATE, $nm, 0)
        Local $idx  = GUICtrlCreateListViewItem($nm & "|" & $path & "|" & ($st = "1" ? "Yes" : "No"), $hListFiles)
        _GUICtrlListView_SetItemChecked($hListFiles, $idx, $st = "1")
        If $st = "1" Then $cnt += 1
    Next

    GUICtrlSetData($hStatusFiles, "Blocked Files: " & $cnt)
    _LoadFileExceptions()
EndFunc


;— إزالة ملف
Func _RemoveFile()
    For $i = _GUICtrlListView_GetItemCount($hListFiles) - 1 To 0 Step -1
        If _GUICtrlListView_GetItemChecked($hListFiles, $i) Then
            ;— 1) احصل على اسم الملف
            Local $nm   = _GUICtrlListView_GetItemText($hListFiles, $i, 0)
            ;— 2) اقرأ المسار من قسم FilePaths
            Local $path = IniRead($INI_FILE, $SECTION_FILE_PATHS, $nm, "")
            ;— 3) ارفع الحظر (إن كان مقفولاً)
            _UnlockFile($path)
            ;— 4) احذف المفاتيح من الأقسام الثلاثة
            IniDelete($INI_FILE, $SECTION_FILE_PATHS, $nm)
            IniDelete($INI_FILE, $SECTION_FILE_STATE, $nm)
            IniDelete($INI_FILE, $SECTION_FILE_EXCEP, $nm)
        EndIf
    Next
    ;— 5) أعد تحميل القائمة لعرض التغيير
    _LoadFileList()
EndFunc



;— تبديل حظر/رفع حظر ملف
Func _ToggleBlockFile($state)
    For $i = 0 To _GUICtrlListView_GetItemCount($hListFiles) - 1
        If _GUICtrlListView_GetItemChecked($hListFiles, $i) Then
            Local $nm = _GUICtrlListView_GetItemText($hListFiles, $i, 0)
            IniWrite($INI_FILE, $SECTION_FILE_STATE, $nm, $state)
            Local $path = IniRead($INI_FILE, $SECTION_FILE_PATHS, $nm, "")
            If $state = 1 Then
                _LockFile($path)
            Else
                _UnlockFile($path)
            EndIf
        EndIf
    Next
    Sleep(100)
    _LoadFileList()
EndFunc

;— جدولة استثناء للملف
Func _ScheduleFileException()
    Local $d1 = @YEAR & "-" & StringFormat("%02d", @MON) & "-" & StringFormat("%02d", @MDAY)
    Local $t1 = StringFormat("%02d:%02d", @HOUR, @MIN)
    Local $sum = @HOUR * 60 + @MIN + 30
    Local $t2h = Mod(Int($sum / 60), 24), $t2m = Mod($sum, 60)
    Local $d2 = $d1, $t2 = StringFormat("%02d:%02d", $t2h, $t2m)

    Local $hDlg = GUICreate("Set Exception…", 430, 180, -1, -1)
    GUISetFont(10, 400)
    GUICtrlCreateLabel("Start Date:", 10, 10, 140, 20)
    Local $hD1 = GUICtrlCreateInput($d1, 155, 10, 120, 20)
    GUICtrlCreateLabel("Start Time:", 285, 10, 100, 20)
    Local $hT1 = GUICtrlCreateInput($t1, 365, 10, 60, 20)
    GUICtrlCreateLabel("End Date:",   10, 50, 140, 20)
    Local $hD2 = GUICtrlCreateInput($d2, 155, 50, 120, 20)
    GUICtrlCreateLabel("End Time:",   285, 50, 100, 20)
    Local $hT2 = GUICtrlCreateInput($t2, 365, 50, 60, 20)
    Local $bOK = GUICtrlCreateButton("OK", 125, 100, 80, 30)
    Local $bC  = GUICtrlCreateButton("Cancel", 245, 100, 80, 30)
    GUISetState(@SW_SHOW)

    While True
        Local $msg = GUIGetMsg()
        If $msg = $bOK Then
            Local $sd = GUICtrlRead($hD1), $st = GUICtrlRead($hT1)
            Local $ed = GUICtrlRead($hD2), $et = GUICtrlRead($hT2)
            If Not StringRegExp($sd, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($st, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            If Not StringRegExp($ed, "^\d{4}-\d{2}-\d{2}$") Then ContinueLoop
            If Not StringRegExp($et, "^(?:[01]\d|2[0-3]):[0-5]\d$") Then ContinueLoop
            GUIDelete($hDlg)

            For $i = 0 To _GUICtrlListView_GetItemCount($hListFiles) - 1
                If _GUICtrlListView_GetItemChecked($hListFiles, $i) Then
                    Local $nm = _GUICtrlListView_GetItemText($hListFiles, $i, 0)
                    IniWrite($INI_FILE, $SECTION_FILE_EXCEP, $nm, $sd & "|" & $st & "|" & $ed & "|" & $et)
                EndIf
            Next

            MsgBox($MB_ICONINFORMATION, "Block Files", _
                "Exception scheduled from " & $sd & " " & $st & @CRLF & "to " & $ed & " " & $et)
            _LoadFileList()
            Return
        ElseIf $msg = $bC Or $msg = $GUI_EVENT_CLOSE Then
            GUIDelete($hDlg)
            Return
        EndIf
    WEnd
EndFunc

;— إزالة استثناء ملف
Func _RemoveFileException()
    For $i = _GUICtrlListView_GetItemCount($hSchedFiles) - 1 To 0 Step -1
        If _GUICtrlListView_GetItemSelected($hSchedFiles, $i) Then
            Local $nm = _GUICtrlListView_GetItemText($hSchedFiles, $i, 0)
            IniDelete($INI_FILE, $SECTION_FILE_EXCEP, $nm)
        EndIf
    Next
    _LoadFileList()
EndFunc

;— قفل الملف (CreateFile و Handle)
Func _LockFile($sFullPath)
    Local $t = DllCall("kernel32.dll", "handle", "CreateFileW", _
        "wstr", $sFullPath, _
        "dword", 0x80000000 + 0x40000000, _   ; GENERIC_READ|GENERIC_WRITE
        "dword", 0, _                         ; no share
        "ptr", 0, _
        "dword", 3, _                         ; OPEN_EXISTING
        "dword", 0x80, _                      ; FILE_ATTRIBUTE_NORMAL
        "ptr", 0)
    If @error Or $t[0] = -1 Then Return
    $g_hFileHandles.Item(StringLower($sFullPath)) = $t[0]
EndFunc

;— رفع الحظر عن الملف
Func _UnlockFile($sFullPath)
    Local $key = StringLower($sFullPath)
    If $g_hFileHandles.Exists($key) Then
        DllCall("kernel32.dll", "int", "CloseHandle", "handle", $g_hFileHandles.Item($key))
        $g_hFileHandles.Remove($key)
    EndIf
EndFunc

;— مراقبة دورية لتنفيذ الحظر/الرفع للتطبيقات والملفات
Func _MonitorBlocked()
    Local $now = @YEAR & "-" & StringFormat("%02d", @MON) & "-" & StringFormat("%02d", @MDAY) & _
                 " " & StringFormat("%02d", @HOUR) & ":" & StringFormat("%02d", @MIN)

    ;— التطبيقات
    Local $a = IniReadSection($INI_FILE, $SECTION_BLOCK)
    If Not @error Then
        For $i = 1 To $a[0][0]
            If $a[$i][1] = "1" Then
                Local $pr = $a[$i][0]
                Local $ex = IniRead($INI_FILE, $SECTION_EXCEP, $pr, "")
                Local $skip = False
                If $ex <> "" Then
                    Local $p = StringSplit($ex, "|")
                    If $now >= $p[1] & " " & $p[2] And $now < $p[3] & " " & $p[4] Then
                        $skip = True
                    ElseIf $now >= $p[3] & " " & $p[4] Then
                        IniDelete($INI_FILE, $SECTION_EXCEP, $pr)
                    EndIf
                EndIf
                If Not $skip And ProcessExists($pr) Then ProcessClose($pr)
            EndIf
        Next
        ;— حدّث جدول استثناءات التطبيقات
        _LoadExceptions()
    EndIf

    ;— الملفات
    Local $af = IniReadSection($INI_FILE, $SECTION_FILE_PATHS)
    If Not @error Then
        For $i = 1 To $af[0][0]
            Local $nm   = $af[$i][0]                      ; اسم الملف
            Local $path = IniRead($INI_FILE, $SECTION_FILE_PATHS, $nm, "")
            Local $st   = IniRead($INI_FILE, $SECTION_FILE_STATE, $nm, 0)
            Local $ex   = IniRead($INI_FILE, $SECTION_FILE_EXCEP, $nm, "")
            Local $inExc = False
            If $ex <> "" Then
                Local $p = StringSplit($ex, "|")
                If $now >= $p[1] & " " & $p[2] And $now < $p[3] & " " & $p[4] Then
                    $inExc = True
                ElseIf $now >= $p[3] & " " & $p[4] Then
                    IniDelete($INI_FILE, $SECTION_FILE_EXCEP, $nm)
                EndIf
            EndIf

            If $st = "1" And Not $inExc Then
                _LockFile($path)
            Else
                _UnlockFile($path)
            EndIf
        Next
        ;— حدّث جدول استثناءات الملفات
        _LoadFileExceptions()
    EndIf
EndFunc

