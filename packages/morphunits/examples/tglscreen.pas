{
    Copyright (c) 2026 Karoly Balogh

    Multibuffered TinyGL screen context creation example
    Example program for Free Pascal's MorphOS bindings

    With thanks to Mark Olsen for his help.

    This example program is in the Public Domain under the terms of
    Unlicense: http://unlicense.org/

 **********************************************************************}

program tglscreen;

uses
  GL, TinyGL, Intuition, Exec, Utility, AmigaDOS;

var
  glScreen: PScreen;

function CreateGLScreen: PScreen;
var
  screen: PScreen;
begin
  screen:=nil;
  if assigned(TinyGLBase) and assigned(tglContext) then
    begin
      screen:=OpenScreenTags(nil,
          [ SA_LikeWorkbench, 1,
            SA_Quiet, 1,
            SA_AdaptSize, 1,
            SA_3DSupport, 1,
            TAG_DONE ]);

      if assigned(screen) then
        begin
          if not GLAInitializeContextTags(tglContext,
                 [ TGL_CONTEXT_SCREEN, Tag(screen),
                   { TGL_CONTEXT_NODEPTH, 1, } { Enable this if no depth buffer is needed. }
                   { TGL_CONTEXT_STENCIL, 1, } { Enable this if stencil buffer is needed. }
                   TAG_DONE ]) then
            begin
              CloseScreen(screen);
              screen:=nil;
            end;
        end;
    end;
  CreateGLScreen:=screen;
end;

procedure RenderGLScreen;
begin
  { Make the screen blue }
  glClearColor(0, 0, 1, 0);
  glClear(GL_COLOR_BUFFER_BIT);

  { TinyGL will handle triple buffering and buffer swapping }
  { Call GLASwapBuffers() when you want the current frame displayed }
  GLASwapBuffers(tglContext);

  DOSDelay(100);
end;

procedure CloseGLScreen(screen: PScreen);
begin
  if assigned(screen) then
    begin
      GLADestroyContext(tglContext);
      CloseScreen(screen);
    end;
end;

begin
  glScreen:=CreateGLScreen;
  RenderGLScreen;
  CloseGLScreen(glScreen);
end.
