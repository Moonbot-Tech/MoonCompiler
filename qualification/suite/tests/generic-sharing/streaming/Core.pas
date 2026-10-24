unit Core;
interface
uses System.Classes;
type
  TStored<T> = class(TComponent)
  private
    FNumber: Integer;
    FCaption: string;
  public
    Item: T;
  published
    property Number: Integer read FNumber write FNumber;
    property Caption: string read FCaption write FCaption;
  end;
implementation
end.
