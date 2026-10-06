{******************************************************************************}
{                                                                              }
{ UI dialog header information API interface unit for Object Pascal            }
{                                                                              }
{ Portions created by Microsoft are Copyright (C) 1995-2001 Microsoft          }
{ Corporation. All Rights Reserved.                                            }
{                                                                              }
{ The original file is: dlgs.h, released June 2000. The original Pascal        }
{ code is: Dlgs.pas, released December 2000. The initial developer of the      }
{ Pascal code is Marcel van Brakel (brakelm att chello dott nl).               }
{                                                                              }
{ Portions created by Marcel van Brakel are Copyright (C) 1999-2001            }
{ Marcel van Brakel. All Rights Reserved.                                      }
{                                                                              }
{ Obtained through: Joint Endeavour of Delphi Innovators (Project JEDI)        }
{                                                                              }
{ You may retrieve the latest version of this file at the Project JEDI         }
{ APILIB home page, located at http://jedi-apilib.sourceforge.net              }
{                                                                              }
{ The contents of this file are used with permission, subject to the Mozilla   }
{ Public License Version 1.1 (the "License"); you may not use this file except }
{ in compliance with the License. You may obtain a copy of the License at      }
{ http://www.mozilla.org/MPL/MPL-1.1.html                                      }
{                                                                              }
{ Software distributed under the License is distributed on an "AS IS" basis,   }
{ WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for }
{ the specific language governing rights and limitations under the License.    }
{                                                                              }
{ Alternatively, the contents of this file may be used under the terms of the  }
{ GNU Lesser General Public License (the  "LGPL License"), in which case the   }
{ provisions of the LGPL License are applicable instead of those above.        }
{ If you wish to allow use of your version of this file only under the terms   }
{ of the LGPL License and not to allow others to use your version of this file }
{ under the MPL, indicate your decision by deleting  the provisions above and  }
{ replace  them with the notice and other provisions required by the LGPL      }
{ License.  If you do not delete the provisions above, a recipient may use     }
{ your version of this file under either the MPL or the LGPL License.          }
{                                                                              }
{ For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html }
{                                                                              }
{******************************************************************************}

// $Id: Dlgs.pas,v 1.9 2007/09/05 11:58:49 dezipaitor Exp $
unit Dlgs;
{$mode delphi}{$H+}{$packrecords c}{$packenum 4}

interface

//
//  Constant Declarations.
//

const
  ctlFirst = $0400;
  ctlLast  = $04ff;

//
//  Push buttons.
//

  psh1    = $0400;
  psh2    = $0401;
  psh3    = $0402;
  psh4    = $0403;
  psh5    = $0404;
  psh6    = $0405;
  psh7    = $0406;
  psh8    = $0407;
  psh9    = $0408;
  psh10   = $0409;
  psh11   = $040a;
  psh12   = $040b;
  psh13   = $040c;
  psh14   = $040d;
  psh15   = $040e;
  pshHelp = psh15;
  psh16   = $040f;

//
//  Checkboxes.
//

  chx1  = $0410;
  chx2  = $0411;
  chx3  = $0412;
  chx4  = $0413;
  chx5  = $0414;
  chx6  = $0415;
  chx7  = $0416;
  chx8  = $0417;
  chx9  = $0418;
  chx10 = $0419;
  chx11 = $041a;
  chx12 = $041b;
  chx13 = $041c;
  chx14 = $041d;
  chx15 = $041e;
  chx16 = $041f;

//
//  Radio buttons.
//

  rad1  = $0420;
  rad2  = $0421;
  rad3  = $0422;
  rad4  = $0423;
  rad5  = $0424;
  rad6  = $0425;
  rad7  = $0426;
  rad8  = $0427;
  rad9  = $0428;
  rad10 = $0429;
  rad11 = $042a;
  rad12 = $042b;
  rad13 = $042c;
  rad14 = $042d;
  rad15 = $042e;
  rad16 = $042f;

//
//  Groups, frames, rectangles, and icons.
//

  grp1 = $0430;
  grp2 = $0431;
  grp3 = $0432;
  grp4 = $0433;
  frm1 = $0434;
  frm2 = $0435;
  frm3 = $0436;
  frm4 = $0437;
  rct1 = $0438;
  rct2 = $0439;
  rct3 = $043a;
  rct4 = $043b;
  ico1 = $043c;
  ico2 = $043d;
  ico3 = $043e;
  ico4 = $043f;

//
//  Static text.
//

  stc1  = $0440;
  stc2  = $0441;
  stc3  = $0442;
  stc4  = $0443;
  stc5  = $0444;
  stc6  = $0445;
  stc7  = $0446;
  stc8  = $0447;
  stc9  = $0448;
  stc10 = $0449;
  stc11 = $044a;
  stc12 = $044b;
  stc13 = $044c;
  stc14 = $044d;
  stc15 = $044e;
  stc16 = $044f;
  stc17 = $0450;
  stc18 = $0451;
  stc19 = $0452;
  stc20 = $0453;
  stc21 = $0454;
  stc22 = $0455;
  stc23 = $0456;
  stc24 = $0457;
  stc25 = $0458;
  stc26 = $0459;
  stc27 = $045a;
  stc28 = $045b;
  stc29 = $045c;
  stc30 = $045d;
  stc31 = $045e;
  stc32 = $045f;

//
//  Listboxes.
//

  lst1  = $0460;
  lst2  = $0461;
  lst3  = $0462;
  lst4  = $0463;
  lst5  = $0464;
  lst6  = $0465;
  lst7  = $0466;
  lst8  = $0467;
  lst9  = $0468;
  lst10 = $0469;
  lst11 = $046a;
  lst12 = $046b;
  lst13 = $046c;
  lst14 = $046d;
  lst15 = $046e;
  lst16 = $046f;

//
//  Combo boxes.
//

  cmb1  = $0470;
  cmb2  = $0471;
  cmb3  = $0472;
  cmb4  = $0473;
  cmb5  = $0474;
  cmb6  = $0475;
  cmb7  = $0476;
  cmb8  = $0477;
  cmb9  = $0478;
  cmb10 = $0479;
  cmb11 = $047a;
  cmb12 = $047b;
  cmb13 = $047c;
  cmb14 = $047d;
  cmb15 = $047e;
  cmb16 = $047f;

//
//  Edit controls.
//

  edt1  = $0480;
  edt2  = $0481;
  edt3  = $0482;
  edt4  = $0483;
  edt5  = $0484;
  edt6  = $0485;
  edt7  = $0486;
  edt8  = $0487;
  edt9  = $0488;
  edt10 = $0489;
  edt11 = $048a;
  edt12 = $048b;
  edt13 = $048c;
  edt14 = $048d;
  edt15 = $048e;
  edt16 = $048f;

//
//  Scroll bars.
//

  scr1 = $0490;
  scr2 = $0491;
  scr3 = $0492;
  scr4 = $0493;
  scr5 = $0494;
  scr6 = $0495;
  scr7 = $0496;
  scr8 = $0497;

//
//  Controls
//

  ctl1 = $04A0;

//
//  These dialog resource ordinals really start at 0x0600, but the
//  RC Compiler can't handle hex for resource IDs, hence the decimal.
//

  FILEOPENORD      = 1536;
  MULTIFILEOPENORD = 1537;
  PRINTDLGORD      = 1538;
  PRNSETUPDLGORD   = 1539;
  FINDDLGORD       = 1540;
  REPLACEDLGORD    = 1541;
  FONTDLGORD       = 1542;
  FORMATDLGORD31   = 1543;
  FORMATDLGORD30   = 1544;
  RUNDLGORD        = 1545;

  PAGESETUPDLGORD      = 1546;
  NEWFILEOPENORD       = 1547;
  PRINTDLGEXORD        = 1549;
  PAGESETUPDLGORDMOTIF = 1550;
  COLORMGMTDLGORD      = 1551;
  NEWFILEOPENV2ORD     = 1552;

//
//  Typedef Declarations.
//

type
  tagCRGB = record
    bRed: BYTE;
    bGreen: BYTE;
    bBlue: BYTE;
    bExtra: BYTE;
  end;
  CRGB = tagCRGB;

implementation
//uses ...

//your implementation here

end.
