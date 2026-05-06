#define MyAppName "Album App"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "OpenAI"
#define MyAppExeName "album_app.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"
#define MyAppOutputDir "..\..\build\installers"

[Setup]
AppId={{A72BA329-3365-4FB8-B71E-71CCF70FB7A6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#MyAppOutputDir}
OutputBaseFilename=album_app_windows_setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: english; MessagesFile: compiler:Default.isl

[Tasks]
Name: desktopicon; Description: Create a desktop shortcut; GroupDescription: Additional shortcuts:

[Files]
Source: {#MyAppSourceDir}\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: {autoprograms}\{#MyAppName}; Filename: {app}\{#MyAppExeName}
Name: {autodesktop}\{#MyAppName}; Filename: {app}\{#MyAppExeName}; Tasks: desktopicon

[Run]
Filename: {app}\{#MyAppExeName}; Description: Launch {#MyAppName}; Flags: nowait postinstall skipifsilent
