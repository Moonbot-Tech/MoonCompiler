unit fpc_41541_anon_record_generic_unit;

{$mode objfpc}

interface

type
  generic TKeywordDictionary<T> = class
  public type
    TBucketArray = array of record
      Key: String;
      Value: T;
    end;
  end;

implementation

end.
