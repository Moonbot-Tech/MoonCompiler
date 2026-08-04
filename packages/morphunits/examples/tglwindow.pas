{
    Copyright (c) 2026 Karoly Balogh

    Multibuffered TinyGL window context creation example
    Example program for Free Pascal's MorphOS bindings

    With thanks to Mark Olsen for his help.

    This example program is in the Public Domain under the terms of
    Unlicense: http://unlicense.org/

 **********************************************************************}

program tglwindow;

uses
  GL, TinyGL, Intuition, Exec, Utility, AmigaDOS;

var
  glWindow: PWindow;

const
  WIDTH = 640;
  HEIGHT = 480;

function CreateGLWindow(w, h: dword): PWindow;
var
  window: PWindow;
  pubscreen: PScreen;
  x, y: DWord;
begin
  CreateGLWindow:=nil;
  window:=nil;

  if assigned(TinyGLBase) and assigned(tglContext) then
    begin
      pubscreen:=LockPubScreen(nil);
      if not assigned(pubscreen) then
        exit;

      x:=(pubscreen^.Width div 2) - (w div 2);
      y:=(pubscreen^.Height div 2) - (h div 2);

      window:=OpenWindowTags(nil,
          [ WA_SimpleRefresh, 1,
            WA_Activate, 1,
            WA_Left, x,
            WA_Top, y,
            WA_InnerWidth, w,
            WA_InnerHeight, h,
            WA_MinWidth, w,
            WA_MinHeight, h,
            WA_MaxWidth, w,
            WA_MaxHeight, h,
            WA_PubScreen, Tag(pubscreen),
            WA_Title, Tag(PChar('FPC TinyGL Window')),
            WA_Flags, WFLG_DRAGBAR or WFLG_DEPTHGADGET,
            TAG_DONE ]);

      UnlockPubScreen(nil, pubscreen);

      if assigned(window) then
        begin
          if not GLAInitializeContextTags(tglContext,
                 [ TGL_CONTEXT_WINDOW, Tag(window),
                   { TGL_CONTEXT_NODEPTH, 1, } { Enable this if no depth buffer is needed. }
                   { TGL_CONTEXT_STENCIL, 1, } { Enable this if stencil buffer is needed. }
                   TAG_DONE ]) then
            begin
              CloseWindow(window);
              window:=nil;
            end;
        end;
    end;
  CreateGLWindow:=window;
end;

procedure RenderGLWindow;
begin
  { Make the window blue }
  glClearColor(0, 0, 1, 0);
  glClear(GL_COLOR_BUFFER_BIT);

  { TinyGL will handle double buffering and buffer swapping }
  { Call GLASwapBuffers() when you want the current frame displayed }
  GLASwapBuffers(tglContext);

  DOSDelay(100);
end;

procedure CloseGLWindow(window: PWindow);
begin
  if assigned(window) then
    begin
      GLADestroyContext(tglContext);
      CloseWindow(window);
    end;
end;

begin
  glWindow:=CreateGLWindow(WIDTH, HEIGHT);
  RenderGLWindow;
  CloseGLWindow(glWindow);
end.
