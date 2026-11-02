#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shellapi.h>
#include <iostream>
#include <sstream>
#include <vector>
#include <string>
#include <filesystem>
#include <regex>


namespace fs = std::filesystem;

std::wstring g_currentFile;

#pragma comment(lib, "comctl32.lib")

#define main cli_main
#include "main.cpp"
#undef main

// Global Variables
HINSTANCE hInst;
HWND hMainWnd;
HWND hListView;
HWND hBtnSelectExtract;
HWND hBtnAllExtract;
HWND hStatusBar;

// Control IDs
#define IDC_LISTVIEW 1001
// Control IDs
#define IDC_LISTVIEW 1001
#define IDC_BTN_SELECT_EXTRACT 1002
#define IDC_BTN_ALL_EXTRACT 1003
#define IDC_STATUSBAR 1004
#define ID_FILE_OPEN 2001
#define ID_FILE_EXIT 2002
#define ID_HELP_ABOUT 2003
#define ID_FILE_EXIT 2002
#define ID_HELP_ABOUT 2003
#define IDI_ICON1 101
#define IDD_ABOUTBOX 2004
#define IDD_ABOUTBOX 2004
#define IDC_BIGICON 2005
#define IDC_SYSLINK 2006

// Function Prototypes
LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
INT_PTR CALLBACK About(HWND, UINT, WPARAM, LPARAM);
void AddListViewItems(const std::string& output);
void InitListViewColumns(HWND hList);
void ProcessFile(const std::wstring& filePath);
void CaptureAndPopulate(const std::vector<std::string>& args);
void ExtractFiles(const std::vector<std::string>& files);
void OnSelectExtract();
void OnAllExtract();
void OnFileOpen();
void OnAllExtract();
void OnFileOpen();
void OnHelpAbout();
void SetModernFont(HWND hWnd);
std::string BrowseForFolder(HWND hwnd);

// File system paths use the active code page (UTF-8 via the manifest), archive names use UTF-8
static std::string WideToNarrow(const std::wstring& ws, UINT codePage = CP_ACP) {
    if (ws.empty()) return "";
    int len = WideCharToMultiByte(codePage, 0, ws.c_str(), (int)ws.size(), NULL, 0, NULL, NULL);
    std::string s(len, 0);
    WideCharToMultiByte(codePage, 0, ws.c_str(), (int)ws.size(), &s[0], len, NULL, NULL);
    return s;
}

static std::wstring NarrowToWide(const std::string& s, UINT codePage = CP_UTF8) {
    if (s.empty()) return L"";
    int len = MultiByteToWideChar(codePage, 0, s.c_str(), (int)s.size(), NULL, 0);
    std::wstring ws(len, 0);
    MultiByteToWideChar(codePage, 0, s.c_str(), (int)s.size(), &ws[0], len);
    return ws;
}



int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    hInst = hInstance;
    INITCOMMONCONTROLSEX icex;
    icex.dwSize = sizeof(INITCOMMONCONTROLSEX);
    icex.dwICC = ICC_LISTVIEW_CLASSES | ICC_BAR_CLASSES | ICC_LINK_CLASS;
    InitCommonControlsEx(&icex);

    WNDCLASSEX wc = {0};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_ICON1));
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = L"SynoXtractGUI";
    wc.hIconSm = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_ICON1));

    RegisterClassEx(&wc);

    hMainWnd = CreateWindowEx(
        WS_EX_ACCEPTFILES,
        L"SynoXtractGUI",
        L"SynoXtract GUI",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
        NULL, NULL, hInstance, NULL
    );

    if (!hMainWnd) return FALSE;

    ShowWindow(hMainWnd, nCmdShow);
    UpdateWindow(hMainWnd);

    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return (int)msg.wParam;
}

LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE: {
        RECT rcClient;
        GetClientRect(hWnd, &rcClient);

        // Menu
        HMENU hMenu = CreateMenu();
        
        HMENU hFileMenu = CreatePopupMenu();
        AppendMenu(hFileMenu, MF_STRING, ID_FILE_OPEN, L"&Open...");
        AppendMenu(hFileMenu, MF_SEPARATOR, 0, NULL);
        AppendMenu(hFileMenu, MF_STRING, ID_FILE_EXIT, L"E&xit");
        AppendMenu(hMenu, MF_STRING | MF_POPUP, (UINT_PTR)hFileMenu, L"&File");

        HMENU hHelpMenu = CreatePopupMenu();
        AppendMenu(hHelpMenu, MF_STRING, ID_HELP_ABOUT, L"&About");
        AppendMenu(hMenu, MF_STRING | MF_POPUP, (UINT_PTR)hHelpMenu, L"&Help");

        // Set Menu Background Color
        MENUINFO mi = { 0 };
        mi.cbSize = sizeof(MENUINFO);
        mi.fMask = MIM_BACKGROUND | MIM_APPLYTOSUBMENUS;
        mi.hbrBack = CreateSolidBrush(GetSysColor(COLOR_BTNFACE));
        
        SetMenu(hWnd, hMenu);
        SetMenuInfo(hMenu, &mi);
        DrawMenuBar(hWnd);

        // Create ListView
        hListView = CreateWindowEx(
            WS_EX_CLIENTEDGE, WC_LISTVIEW, L"",
            WS_CHILD | WS_VISIBLE | LVS_REPORT,
            0, 0, rcClient.right, rcClient.bottom - 50,
            hWnd, (HMENU)IDC_LISTVIEW, hInst, NULL
        );
        ListView_SetExtendedListViewStyle(hListView, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES);
        InitListViewColumns(hListView);
        SetModernFont(hListView);

        // Create Buttons
        hBtnSelectExtract = CreateWindow(
            L"BUTTON", L"Select Extract",
            WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
            10, rcClient.bottom - 40, 120, 30,
            hWnd, (HMENU)IDC_BTN_SELECT_EXTRACT, hInst, NULL
        );
        SetModernFont(hBtnSelectExtract);

        hBtnAllExtract = CreateWindow(
            L"BUTTON", L"All Extract",
            WS_TABSTOP | WS_VISIBLE | WS_CHILD,
            140, rcClient.bottom - 40, 120, 30,
            hWnd, (HMENU)IDC_BTN_ALL_EXTRACT, hInst, NULL
        );
        SetModernFont(hBtnAllExtract);

        // Create StatusBar
        hStatusBar = CreateWindowEx(
            0, STATUSCLASSNAME, NULL,
            WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
            0, 0, 0, 0,
            hWnd, (HMENU)IDC_STATUSBAR, hInst, NULL
        );
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Ready - Open or Drop a .pat/.spk file");
        SetModernFont(hStatusBar);
        
        break;
    }
    case WM_SIZE: {
        RECT rcClient;
        GetClientRect(hWnd, &rcClient);
        
        int btnWidth = 120;
        int btnHeight = 30;
        int gap = 20;
        int totalWidth = (btnWidth * 2) + gap;
        int startX = (rcClient.right - totalWidth) / 2;
        
        int btnY = rcClient.bottom - 60; 

        int listMargin = 10;
        MoveWindow(hListView, listMargin, listMargin, rcClient.right - (2 * listMargin), btnY - listMargin - 15, TRUE);
        
        MoveWindow(hBtnSelectExtract, startX, btnY, btnWidth, btnHeight, TRUE);
        MoveWindow(hBtnAllExtract, startX + btnWidth + gap, btnY, btnWidth, btnHeight, TRUE);
        SendMessage(hStatusBar, WM_SIZE, 0, 0);

        // Auto-resize Name column to fill width
        int totalColWidth = 0;
        for (int i = 0; i < 5; i++) {
            totalColWidth += ListView_GetColumnWidth(hListView, i);
        }
        int newNameWidth = (rcClient.right - (2 * listMargin)) - totalColWidth - 4;
        if (newNameWidth < 100) newNameWidth = 100;
        ListView_SetColumnWidth(hListView, 5, newNameWidth);

        break;
    }
    case WM_DROPFILES: {
        HDROP hDrop = (HDROP)wParam;
        wchar_t filePath[MAX_PATH];
        if (DragQueryFile(hDrop, 0, filePath, MAX_PATH)) {
            ProcessFile(filePath);
        }
        DragFinish(hDrop);
        break;
    }
    case WM_COMMAND:
        if (HIWORD(wParam) == BN_CLICKED) {
            switch (LOWORD(wParam)) {
            case IDC_BTN_SELECT_EXTRACT:
                OnSelectExtract();
                break;
            case IDC_BTN_ALL_EXTRACT:
                OnAllExtract();
                break;
            }
        }
        if (LOWORD(wParam) == ID_FILE_OPEN) {
            OnFileOpen();
        }
        if (LOWORD(wParam) == ID_FILE_EXIT) {
            PostQuitMessage(0);
        }
        if (LOWORD(wParam) == ID_HELP_ABOUT) {
            OnHelpAbout();
        }
        break;

    case WM_DESTROY:
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

void InitListViewColumns(HWND hList) {
    LVCOLUMN lvc;
    lvc.mask = LVCF_FMT | LVCF_WIDTH | LVCF_TEXT | LVCF_SUBITEM;

    const wchar_t* cols[] = { L"Mode", L"UID", L"GID", L"Size", L"Date", L"Name" };
    int widths[] = { 80, 50, 50, 80, 120, 300 };

    for (int i = 0; i < 6; i++) {
        lvc.iSubItem = i;
        lvc.pszText = const_cast<LPWSTR>(cols[i]);
        lvc.cx = widths[i];
        lvc.fmt = LVCFMT_LEFT;
        ListView_InsertColumn(hList, i, &lvc);
    }
}

void ProcessFile(const std::wstring& filePath) {
    g_currentFile = filePath;
    SetWindowText(hMainWnd, (L"SynoXtract GUI - " + filePath).c_str());
    SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Processing...");
    
    std::string pathStr = WideToNarrow(filePath);
    std::vector<std::string> args = {"synoxtract", "-i", pathStr, "-l"};
    CaptureAndPopulate(args);
}

void CaptureAndPopulate(const std::vector<std::string>& args) {
    // 1. Redirect cout and cerr
    std::streambuf* oldCout = std::cout.rdbuf();
    std::streambuf* oldCerr = std::cerr.rdbuf();
    std::ostringstream captureOut;
    std::ostringstream captureErr;
    std::cout.rdbuf(captureOut.rdbuf());
    std::cerr.rdbuf(captureErr.rdbuf());

    // 2. Prepare argv
    std::vector<char*> argv;
    for (const auto& s : args) {
        argv.push_back(const_cast<char*>(s.c_str()));
    }
    int argc = (int)argv.size();

    // 3. Call cli_main
    int ret = -1;
    try {
        ret = cli_main(argc, argv.data());
    } catch (const std::exception& e) {
        captureErr << "Exception: " << e.what();
    } catch (...) {
        captureErr << "Unknown exception";
    }

    // 4. Restore streams
    std::cout.rdbuf(oldCout);
    std::cerr.rdbuf(oldCerr);

    // 5. Check for errors
    if (ret != 0) {
        std::string err = captureErr.str();
        if (err.empty()) err = "Failed to process file. It may be invalid or corrupted.";
        
        // Convert to wstring for Messagebox
        std::wstring wErr = NarrowToWide(err, CP_ACP);
        
        MessageBox(hMainWnd, wErr.c_str(), L"Error", MB_ICONERROR);
        
        ListView_DeleteAllItems(hListView);
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Error");
        SetWindowText(hMainWnd, L"SynoXtract GUI");
        return;
    }

    // 6. Populate List
    AddListViewItems(captureOut.str());
}

void AddListViewItems(const std::string& output) {
    ListView_DeleteAllItems(hListView);
    std::istringstream iss(output);
    std::string line;
    std::string detectedKeyType = "";

    while (std::getline(iss, line)) {
        // Check for info messages
        if (line.find("[INFO] Detected keytype:") != std::string::npos) {
            size_t pos = line.find("Detected keytype:");
            if (pos != std::string::npos) {
                detectedKeyType = line.substr(pos);
            }
            continue;
        }
        if (line.empty() || line[0] == '[') continue;

        // Use regex for robust parsing
        std::regex re(R"(([d-][rwx-]{9})\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s+(.+))");
        std::smatch match;
        if (std::regex_match(line, match, re)) {
            // match[1] = Mode
            // match[2] = UID, [3] = GID, [4] = Size, [5] = Date, [6] = Name
            
            std::string mode = match[1];
            std::string uid = match[2];
            std::string gid = match[3];
            std::string size = match[4];
            std::string date = match[5];
            std::string name = match[6];

            LVITEM item;
            item.mask = LVIF_TEXT;
            item.iItem = ListView_GetItemCount(hListView);
            item.iSubItem = 0;
            
            std::wstring wMode(mode.begin(), mode.end());
            item.pszText = (LPWSTR)wMode.c_str();
            int idx = ListView_InsertItem(hListView, &item);

            if (idx != -1) {
                std::wstring wUid(uid.begin(), uid.end());
                ListView_SetItemText(hListView, idx, 1, (LPWSTR)wUid.c_str());
                
                std::wstring wGid(gid.begin(), gid.end());
                ListView_SetItemText(hListView, idx, 2, (LPWSTR)wGid.c_str());

                std::wstring wSize(size.begin(), size.end());
                ListView_SetItemText(hListView, idx, 3, (LPWSTR)wSize.c_str());

                std::wstring wDate(date.begin(), date.end());
                ListView_SetItemText(hListView, idx, 4, (LPWSTR)wDate.c_str());
                
                std::wstring wName = NarrowToWide(name);
                ListView_SetItemText(hListView, idx, 5, (LPWSTR)wName.c_str());
            }
        }
    }
    
    if (!detectedKeyType.empty()) {
        std::wstring wStatus(detectedKeyType.begin(), detectedKeyType.end());
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)wStatus.c_str());
    } else {
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Done listing files.");
    }
}

void ExtractFiles(const std::vector<std::string>& files) {
    if (g_currentFile.empty()) {
        MessageBox(hMainWnd, L"No file loaded!", L"Error", MB_ICONERROR);
        return;
    }

    SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Extracting...");
    
    // Determine dest dir: ./<filename_no_ext>/
    fs::path p(g_currentFile);
    fs::path destDir = p.parent_path() / p.stem();
    std::string destDirStr = WideToNarrow(destDir.wstring());

    std::wstring msg = L"Extract to default folder?\n\n" + destDir.wstring() + L"\n\nSelect 'Yes' for default, 'No' to choose location, 'Cancel' to abort.";
    int result = MessageBox(hMainWnd, msg.c_str(), L"Extract to...", MB_YESNOCANCEL | MB_ICONQUESTION);
    
    if (result == IDCANCEL) {
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Extraction Canceled");
        return;
    }

    if (result == IDNO) {
        std::string customPath = BrowseForFolder(hMainWnd);
        if (customPath.empty()) {
            SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Extraction Canceled");
            return;
        }
        destDirStr = customPath;
        destDir = NarrowToWide(customPath, CP_ACP);
    }

    std::string inFileStr = WideToNarrow(g_currentFile);

    std::vector<std::string> args = {"synoxtract", "-i", inFileStr, "-d", destDirStr};
    
    if (!files.empty()) {
         args.push_back("-f");
         for (const auto& f : files) args.push_back(f);
    }

    std::streambuf* oldCout = std::cout.rdbuf();
    std::streambuf* oldCerr = std::cerr.rdbuf();
    std::ostringstream captureOut;
    std::ostringstream captureErr;
    std::cout.rdbuf(captureOut.rdbuf());
    std::cerr.rdbuf(captureErr.rdbuf());

    std::vector<char*> argv;
    for (const auto& s : args) argv.push_back(const_cast<char*>(s.c_str()));
    
    int ret = -1;
    bool exceptionThrown = false;
    std::string errMsg = "";

    try {
        ret = cli_main((int)argv.size(), argv.data());
    } catch (const std::exception& e) {
        exceptionThrown = true;
        errMsg = e.what();
        captureErr << "Exception: " << e.what();
    } catch (...) {
        exceptionThrown = true;
        errMsg = "Unknown exception";
        captureErr << "Unknown exception";
    }

    std::cout.rdbuf(oldCout);
    std::cerr.rdbuf(oldCerr);

    if (ret == 0 && !exceptionThrown) {
        std::wstring msg = L"Extraction complete to " + destDir.wstring();
        MessageBox(hMainWnd, msg.c_str(), L"Success", MB_OK);
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Ready");
    } else {
        std::string capturedErr = captureErr.str();
        if (capturedErr.empty()) capturedErr = errMsg;
        if (capturedErr.empty()) capturedErr = "Extraction failed with unknown error.";
        
        std::string fullErr = "Extraction failed:\n" + capturedErr;
        
        // Convert to wstring
        std::wstring wErr = NarrowToWide(fullErr, CP_ACP);

        MessageBox(hMainWnd, wErr.c_str(), L"Error", MB_ICONERROR);
        SendMessage(hStatusBar, SB_SETTEXT, 0, (LPARAM)L"Extraction Failed");
    }
}

void OnSelectExtract() {
    std::vector<std::string> selectedFiles;
    int iPos = -1;
    while ((iPos = ListView_GetNextItem(hListView, iPos, LVNI_SELECTED)) != -1) {
        wchar_t buf[1024];
        ListView_GetItemText(hListView, iPos, 5, buf, 1024);
        std::wstring ws(buf);
        selectedFiles.push_back(WideToNarrow(ws, CP_UTF8));
    }

    if (selectedFiles.empty()) {
        MessageBox(hMainWnd, L"No files selected.", L"Warning", MB_ICONWARNING);
        return;
    }
    ExtractFiles(selectedFiles);
}


void OnAllExtract() {
    ExtractFiles({});
}

void OnFileOpen() {
    OPENFILENAME ofn;
    wchar_t szFile[MAX_PATH] = {0};

    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = hMainWnd;
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrFilter = L"Synology Images (*.pat;*.spk)\0*.pat;*.spk\0All Files (*.*)\0*.*\0";
    ofn.nFilterIndex = 1;
    ofn.lpstrFileTitle = NULL;
    ofn.nMaxFileTitle = 0;
    ofn.lpstrInitialDir = NULL;
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    if (GetOpenFileName(&ofn) == TRUE) {
        ProcessFile(ofn.lpstrFile);
    }
}

void OnHelpAbout() {
    DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUTBOX), hMainWnd, About);
}

// Message handler for about box.
INT_PTR CALLBACK About(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
{
    UNREFERENCED_PARAMETER(lParam);
    static HICON hIconBig = NULL;

    switch (message)
    {
    case WM_INITDIALOG:
        hIconBig = (HICON)LoadImage(hInst, MAKEINTRESOURCE(IDI_ICON1), IMAGE_ICON, 128, 128, LR_DEFAULTCOLOR);
        if (hIconBig) {
            SendDlgItemMessage(hDlg, IDC_BIGICON, STM_SETIMAGE, IMAGE_ICON, (LPARAM)hIconBig);
        }
        return (INT_PTR)TRUE;

    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
        {
            EndDialog(hDlg, LOWORD(wParam));
            return (INT_PTR)TRUE;
        }
        break;

    case WM_NOTIFY:
        switch (((LPNMHDR)lParam)->code)
        {
        case NM_CLICK:
        case NM_RETURN:
            {
                PNMLINK pNMLink = (PNMLINK)lParam;
                if (pNMLink->hdr.idFrom == IDC_SYSLINK) {
                    ShellExecute(NULL, L"open", pNMLink->item.szUrl, NULL, NULL, SW_SHOWNORMAL);
                    return (INT_PTR)TRUE;
                }
            }
            break;
        }
        break;
    
    case WM_DESTROY:
        if (hIconBig) DestroyIcon(hIconBig);
        break;
    }
    return (INT_PTR)FALSE;
}

void SetModernFont(HWND hWnd) {
    static HFONT hFont = NULL;
    if (!hFont) {
        NONCLIENTMETRICS ncm;
        ncm.cbSize = sizeof(NONCLIENTMETRICS);
        SystemParametersInfo(SPI_GETNONCLIENTMETRICS, sizeof(NONCLIENTMETRICS), &ncm, 0);
        hFont = CreateFontIndirect(&ncm.lfMessageFont);
    }
    SendMessage(hWnd, WM_SETFONT, (WPARAM)hFont, TRUE);
}

std::string BrowseForFolder(HWND hwnd) {
    BROWSEINFO bi = { 0 };
    bi.hwndOwner = hwnd;
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_USENEWUI;
    bi.lpszTitle = L"Select Extraction Destination";

    LPITEMIDLIST pidl = SHBrowseForFolder(&bi);
    if (pidl != 0) {
        wchar_t path[MAX_PATH];
        if (SHGetPathFromIDList(pidl, path)) {
            CoTaskMemFree(pidl);
            return WideToNarrow(path);
        }
        CoTaskMemFree(pidl);
    }
    return "";
}


