{ MoonCompiler 2.1 URL contracts. Written from public declarations and RFCs. }
  TURIParameter = TNameValuePair;
  TURIParameters = array of TURIParameter;

  TURI = record
  private
    FScheme, FUsername, FPassword, FHost, FPath, FQuery, FFragment: string;
    FPort: Integer;
    FParams: TURIParameters;
    procedure SetQuery(const Value: string);
    procedure SetParams(const Value: TURIParameters);
    function GetParameter(I: Integer): TURIParameter;
    procedure SetParameter(I: Integer; const Value: TURIParameter);
    function GetParameterByName(const Name: string): string;
    procedure SetParameterByName(const Name, Value: string);
  public
    constructor Create(const AURIStr: string);
    procedure ComposeURI(const AScheme, AUsername, APassword, AHostname: string; APort: Integer;
      const APath: string; const AParams: TURIParameters; const AFragment: string);
    function ToString: string;
    function Encode: string;
    class operator Implicit(const Value: TURI): string;
    procedure AddParameter(const AName, AValue: string); overload;
    procedure AddParameter(const AParameter: TURIParameter); overload;
    procedure DeleteParameter(AIndex: Integer); overload;
    procedure DeleteParameter(const AName: string); overload;
    class function URLEncode(const Value: string; SpacesAsPlus: Boolean = False): string; static;
    class function URLDecode(const Value: string; PlusAsSpaces: Boolean = False): string; static;
    class function PathRelativeToAbs(const RelPath: string; const Base: TURI): string; static;
    class function FixupForREST(const AURL: string): string; static;
    property Scheme: string read FScheme write FScheme;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property Path: string read FPath write FPath;
    property Query: string read FQuery write SetQuery;
    property Params: TURIParameters read FParams write SetParams;
    property Fragment: string read FFragment write FFragment;
    property Parameter[I: Integer]: TURIParameter read GetParameter write SetParameter;
    property ParameterByName[const Name: string]: string read GetParameterByName write SetParameterByName;
  end;

  TAuthTargetType = (Proxy, Server);
  TAuthPersistenceType = (Request, Client);
  TCredentialsStorage = class(TInterfacedObject)
  public type
    TAuthSchemeType = (Basic, Digest, NTLM, Negotiate);
    TCredential = record
      AuthTarget: TAuthTargetType;
      Realm, URL, UserName, Password: string;
      constructor Create(Target: TAuthTargetType; const ARealm, AURL, AUserName, APassword: string);
      function IsEmpty: Boolean;
    end;
    TCredentialArray = array of TCredential;
    TCredentialAuthCallback = procedure(const Sender: TObject; Target: TAuthTargetType;
      const Realm, URL: string; var UserName, Password: string; var AbortAuth: Boolean;
      var Persistence: TAuthPersistenceType);
    TCredentialAuthEvent = procedure(const Sender: TObject; Target: TAuthTargetType;
      const Realm, URL: string; var UserName, Password: string; var AbortAuth: Boolean;
      var Persistence: TAuthPersistenceType) of object;
  private
    FCredentials: TCredentialArray;
    FLock: TCriticalSection;
    function GetCredentials: TCredentialArray;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ClearCredentials;
    function AddCredential(const Credential: TCredential): Boolean;
    function RemoveCredential(Target: TAuthTargetType; const Realm: string;
      const URL: string = ''; const User: string = ''): Boolean;
    function FindCredentials(Target: TAuthTargetType; const Realm: string;
      const URL: string = ''; const User: string = ''): TCredentialArray;
    function FindAccurateCredential(Target: TAuthTargetType; const Realm: string;
      const URL: string = ''; const User: string = ''): TCredential;
    class function SortCredentials(const Credentials: TCredentialArray): TCredentialArray; static;
    property Credentials: TCredentialArray read GetCredentials;
  end;

  TProxySettings = record
  private
    FHost, FScheme, FUserName, FPassword: string;
    FPort: Integer;
    function GetCredential: TCredentialsStorage.TCredential;
  public
    constructor Create(const URL: string); overload;
    constructor Create(const Host: string; Port: Integer; const UserName: string = '';
      const Password: string = ''; const Scheme: string = ''); overload;
    function ToString: string;
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property Scheme: string read FScheme write FScheme;
    property UserName: string read FUserName write FUserName;
    property Password: string read FPassword write FPassword;
    property Credential: TCredentialsStorage.TCredential read GetCredential;
  end;

  IAsyncResult = Types.IAsyncResult;
  IURLRequest = interface(IInterface)
    function GetCredential: TCredentialsStorage.TCredential;
    procedure SetCredential(const Credential: TCredentialsStorage.TCredential); overload;
    procedure SetCredential(const UserName, Password: string); overload;
    function GetURL: TURI;
    procedure SetURL(const Value: TURI);
    function GetMethodString: string;
    procedure SetMethodString(const Value: string);
    function GetSourceStream: TStream;
    procedure SetSourceStream(const Value: TStream);
    procedure Cancel;
    function GetIsCancelled: Boolean;
    property Credential: TCredentialsStorage.TCredential read GetCredential write SetCredential;
    property URL: TURI read GetURL write SetURL;
    property MethodString: string read GetMethodString write SetMethodString;
    property SourceStream: TStream read GetSourceStream write SetSourceStream;
    property IsCancelled: Boolean read GetIsCancelled;
  end;

  TURLRequest = class(TInterfacedObject, IURLRequest)
  private
    FURL: TURI;
    FMethodString: string;
    FSource: TStream;
    FCredential: TCredentialsStorage.TCredential;
    FCancelled: Longint;
  public
    constructor Create(const AURL, AMethodString: string);
    function GetCredential: TCredentialsStorage.TCredential;
    procedure SetCredential(const Credential: TCredentialsStorage.TCredential); overload;
    procedure SetCredential(const UserName, Password: string); overload;
    function GetURL: TURI;
    procedure SetURL(const Value: TURI);
    function GetMethodString: string;
    procedure SetMethodString(const Value: string);
    function GetSourceStream: TStream;
    procedure SetSourceStream(const Value: TStream);
    procedure Cancel;
    function GetIsCancelled: Boolean;
    property URL: TURI read GetURL write SetURL;
    property MethodString: string read GetMethodString write SetMethodString;
    property SourceStream: TStream read GetSourceStream write SetSourceStream;
    property IsCancelled: Boolean read GetIsCancelled;
  end;

  IURLResponse = interface(IInterface)
    ['{5D687C75-5C36-4302-B0AB-989DDB7558FE}']
    function GetHeaders: TNetHeaders;
    function GetMimeType: string;
    function GetContentStream: TStream;
    function ContentAsString(const Encoding: TEncoding = nil): string;
    function GetAsyncResult: IAsyncResult;
    property Headers: TNetHeaders read GetHeaders;
    property MimeType: string read GetMimeType;
    property ContentStream: TStream read GetContentStream;
    property AsyncResult: IAsyncResult read GetAsyncResult;
  end;

  TURLClient = class;
  TURLAsyncOperation = class;
  TURLAsyncResult = class(TInterfacedObject, IAsyncResult, IURLResponse)
  private
    FOperation: TURLAsyncOperation;
    FCallbackView: Boolean;
  protected
    function AwaitResponse: IURLResponse;
  public
    constructor Create(Operation: TURLAsyncOperation; CallbackView: Boolean = False);
    destructor Destroy; override;
    function GetAsyncContext: TObject;
    function GetAsyncWaitEvent: TMultiWaitEvent;
    function GetCompletedSynchronously: Boolean;
    function GetIsCompleted: Boolean;
    function GetIsCancelled: Boolean;
    function Cancel: Boolean;
    function GetHeaders: TNetHeaders;
    function GetMimeType: string;
    function GetContentStream: TStream;
    function ContentAsString(const Encoding: TEncoding = nil): string;
    function GetAsyncResult: IAsyncResult;
  end;
  TURLAsyncResultClass = class of TURLAsyncResult;

  TURLClient = class
  private type
    TTransport = record
      Scheme: string;
      Client: TURLClient;
    end;
  private
    FTransports: array of TTransport;
    FTransportLock: TCriticalSection;
    function TransportFor(const Scheme: string): TURLClient;
  protected
    FConnectionTimeout, FSendTimeout, FResponseTimeout: Integer;
    FCustomHeaders: TURLHeaders;
    FProxySettings: TProxySettings;
    FCredentialsStorage, FInternalCredentialsStorage: TCredentialsStorage;
    FSharedCredentials: IInterface;
    FAuthCallback: TCredentialsStorage.TCredentialAuthCallback;
    FAuthEvent: TCredentialsStorage.TCredentialAuthEvent;
    function GetCustomHeader(const Name: string): string;
    procedure SetCustomHeader(const Name, Value: string);
    function GetUserAgent: string;
    procedure SetUserAgent(const Value: string);
    procedure CopySettingsTo(Target: TURLClient); virtual;
    function CloneClient(const Scheme: string): TURLClient; virtual;
    function AsyncResultClass: TURLAsyncResultClass; virtual;
    procedure Abort; virtual;
    function DoExecute(const Request: IURLRequest; Content: TStream; const Headers: TNetHeaders): IURLResponse; virtual;
    function StartAsync(const Callback: TAsyncCallback; const CallbackEvent: TAsyncCallbackEvent;
      const Request: IURLRequest; Content: TStream; const Headers: TNetHeaders;
      OwnedSource: TStream = nil): IAsyncResult;
  public
    const DefaultConnectionTimeout = 60000;
    const DefaultSendTimeout = 60000;
    const DefaultResponseTimeout = 60000;
    constructor Create; virtual;
    destructor Destroy; override;
    function GetRequest(const Method: string; const URI: TURI): IURLRequest; overload;
    function GetRequest(const Method, URI: string): IURLRequest; overload;
    function Execute(const Method, URI: string; const Source: TStream = nil; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IURLResponse; overload;
    function Execute(const Method: string; const URI: TURI; const Source: TStream = nil; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IURLResponse; overload;
    function Execute(const Request: IURLRequest; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IURLResponse; overload; virtual;
    function BeginExecute(const Method, URI: string; const Source: TStream = nil; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IAsyncResult; overload;
    function BeginExecute(const Method: string; const URI: TURI; const Source: TStream = nil; const Content: TStream = nil;
      const Headers: TNetHeaders = nil): IAsyncResult; overload;
    function BeginExecute(const Callback: TAsyncCallback; const Method, URI: string; const Source: TStream = nil;
      const Content: TStream = nil; const Headers: TNetHeaders = nil): IAsyncResult; overload;
    function BeginExecute(const Callback: TAsyncCallback; const Method: string; const URI: TURI;
      const Source: TStream = nil; const Content: TStream = nil; const Headers: TNetHeaders = nil): IAsyncResult; overload;
    function BeginExecute(const Callback: TAsyncCallbackEvent; const Method, URI: string; const Source: TStream = nil;
      const Content: TStream = nil; const Headers: TNetHeaders = nil): IAsyncResult; overload;
    function BeginExecute(const Callback: TAsyncCallbackEvent; const Method: string; const URI: TURI;
      const Source: TStream = nil; const Content: TStream = nil; const Headers: TNetHeaders = nil): IAsyncResult; overload;
    class function EndAsyncURL(const AsyncResult: IAsyncResult): IURLResponse; overload; static;
    class function EndAsyncURL(const AsyncResponse: IURLResponse): IURLResponse; overload; static;
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property SendTimeout: Integer read FSendTimeout write FSendTimeout;
    property ResponseTimeout: Integer read FResponseTimeout write FResponseTimeout;
    property UserAgent: string read GetUserAgent write SetUserAgent;
    property CustomHeaders[const Name: string]: string read GetCustomHeader write SetCustomHeader;
    property CustHeaders: TURLHeaders read FCustomHeaders;
    property ProxySettings: TProxySettings read FProxySettings write FProxySettings;
    property CredentialsStorage: TCredentialsStorage read FCredentialsStorage write FCredentialsStorage;
    property AuthCallback: TCredentialsStorage.TCredentialAuthCallback read FAuthCallback write FAuthCallback;
    property AuthEvent: TCredentialsStorage.TCredentialAuthEvent read FAuthEvent write FAuthEvent;
  end;
  TURLClientClass = class of TURLClient;
  TURLSchemes = class
  public
    class procedure RegisterURLClientScheme(ClientClass: TURLClientClass; const Scheme: string); static;
    class procedure UnRegisterURLClientScheme(const Scheme: string); static;
    class function GetURLClientInstance(const Scheme: string): TURLClient; static;
  end;

  { Shared operation owns the clone and completion data; its worker owns one
    reference. Views retain it separately, so callback release cannot destroy
    a worker's stack or create a response/result reference cycle. }
  TURLAsyncOperation = class(TInterfacedObject)
  private
    FLock: TCriticalSection;
    FDone, FCallbacksDone: TMultiWaitEvent;
    FWorkerThread: TThreadID;
    FClient: TURLClient;
    FRequest: IURLRequest;
    FContent, FOwnedSource: TStream;
    FHeaders: TNetHeaders;
    FResponse: IURLResponse;
    FError: Exception;
    FContext: TObject;
    FCallback: TAsyncCallback;
    FCallbackEvent: TAsyncCallbackEvent;
    FResultClass: TURLAsyncResultClass;
    FViews: Integer;
    FCompleted, FCancelled: Boolean;
    procedure Run;
    function NewView(CallbackView: Boolean = False): IAsyncResult;
    procedure DetachView;
    function Cancel: Boolean;
    function Await: IURLResponse;
  public
    constructor Create(Client: TURLClient; const Request: IURLRequest; Content, OwnedSource: TStream;
      const Headers: TNetHeaders; Context: TObject; const Callback: TAsyncCallback;
      const CallbackEvent: TAsyncCallbackEvent; ResultClass: TURLAsyncResultClass);
    destructor Destroy; override;
  end;
