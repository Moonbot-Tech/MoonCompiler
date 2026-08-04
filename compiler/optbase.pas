{
    Basic node optimizer stuff

    Copyright (c) 2007 by Florian Klaempfl

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit optbase;

{$i fpcdefs.inc}

  interface

    uses
      globtype,cdynset;

    type
      { this should maybe replaced by a spare set,
        using a dyn. array makes assignments cheap }
      tdfaset = TDynSet;
      PDFASet = ^TDynSet;

      toptinfo = record
        { index of the current node inside the dfa sets }
        index : aword;
        { dfa }
        def : tdfaset;
        use : tdfaset;
        life : tdfaset;
        { all definitions made by this node and its children }
        defsum : tdfaset;
        { all used nodes by this node and its children }
        usesum : tdfaset;
        avail : tdfaset;
        { estimation, how often the node is executed per subroutine call times 100, calculated by optutils.CalcExecutionWeight }
        executionweight : longint;
      end;

      poptinfo = ^toptinfo;

  implementation

end.
