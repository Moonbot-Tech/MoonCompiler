{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2024 by Michael Van Canneyt
    member of the Free Pascal development team

    Delphi-compatible threading unit

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit System.Threading;

interface

{$mode objfpc}
{$h+}
{$SCOPEDENUMS ON}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch advancedrecords}
{$macro on}
{$ifdef MOONCOMPILER_DELPHI_CALLBACK_TYPES}
{$modeswitch implicitgenerics}
{$define THREADING_GENERIC:=}
{$define THREADING_SPECIALIZE:=}
{$define THREADING_PARAMS:=<T>}
{$define THREADING_PROC2:=TProc}
{$else}
{$define THREADING_GENERIC:=generic}
{$define THREADING_SPECIALIZE:=specialize}
{$define THREADING_PARAMS:=}
{$define THREADING_PROC2:=TProc2}
{$endif}

{ $DEFINE DEBUGTHREADPOOL}

{$IFDEF CPU64}
{$DEFINE THREAD64BIT}
{$ENDIF}

uses
{$IFDEF FPC_DOTTEDUNITS}
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Timespan, System.SyncObjs, System.Contnrs, Fcl.ThreadPool;
{$ELSE}
  Contnrs, SysUtils, Classes, System.Timespan, Generics.Collections, SyncObjs, fpthreadpool;
{$ENDIF}

type
  TLightweightEvent = TEvent;
  
  THREADING_GENERIC TFunctionEvent<T> = function (Sender: TObject): T of object;
{$IFDEF MOONCOMPILER_DELPHI_CALLBACK_TYPES}
{$IFDEF FPC_DOTTEDUNITS}
  TProcRef = System.SysUtils.TProc;
{$ELSE}
  TProcRef = SysUtils.TProc;
{$ENDIF}
{$ELSE}
  THREADING_GENERIC TProc<T> = reference to procedure (arg : T);
  THREADING_GENERIC TProc2<T1,T2> = reference to procedure (arg1 : T1;arg2 : T2);
  THREADING_GENERIC TFunc<T> = Reference to function : T;
  TProcRef = Reference to Procedure;
{$ENDIF}

  TExceptionHandlerEvent = procedure (const aException: Exception; var aHandled: Boolean) of object;
  TExceptionHandlerProc = reference to procedure (const aException: Exception; var aHandled: Boolean);
  TExceptionArray = Array of Exception;

  TTask = class;

  { EAggregateException }

  { TExceptionList }
  // Does not own the exceptions
  TExceptionList = Record
    List : TExceptionArray;
    Count : Integer;
    Class function Create(aCapacity : Integer) : TExceptionList; static;
    Class function Create(Initial : Exception; aCapacity : Integer) : TExceptionList; static;
    Class function Create(aExceptionArray: array of Exception) : TExceptionList; static;
    Procedure AddFromTask(aTask : TTask);
    Procedure Add(aException : Exception);
    Function GrowCapacity(aMinCapacity : Integer) : Integer;
    Function Capacity : Integer;
    function Truncate : TExceptionArray;
    // Will free exceptions.
    procedure ClearList;
    // Expands Aggregate exception. Clears list of exceptions
    procedure Flatten(aException: Exception);
  end;

  EAggregateException = class(Exception)
  Private
    FList: TExceptionList;
    function GetInnerException(aIndex: Integer): Exception;
    procedure clearlist;
  public
    type

    { TExceptionEnumerator }

    TExceptionEnumerator = class
    private
      FException : EAggregateException;
      FCurrent : Integer;
      function GetCurrent: Exception;
    public
      constructor Create(aException : EAggregateException);
      function MoveNext: Boolean; inline;
      property Current: Exception read GetCurrent;
    end;
  Public
    const MaxLoggedExceptions = 10;
  public
    constructor Create(const aExceptionArray: array of Exception); overload;
    constructor Create(const aMessage: string; const aExceptionArray: array of Exception); overload;
    destructor Destroy; override;
    function GetEnumerator: TExceptionEnumerator; inline;
    procedure Handle(aExceptionHandlerEvent: TExceptionHandlerEvent); overload;
    procedure Handle(const aExceptionHandlerProc: TExceptionHandlerProc); overload;
    procedure Add(aException: Exception);
    function ToString: RTLString; override;
    property Count: Integer read FList.Count;
    property InnerExceptions[aIndex: Integer]: Exception read GetInnerException; default;
  end;

  { TSparseArray }

  THREADING_GENERIC TSparseArray<T: class> = class
  public
    Type
      TArrayOfT = THREADING_SPECIALIZE TArray<T>;
  private
    FArray: TArrayOfT;
    FLock: TSpinLock;
  public
    constructor Create(aInitialSize: Integer);
    destructor Destroy; override;
    function Add(const aItem: T): Integer;
    procedure Lock;
    function Remove(const aItem: T) : Boolean;
    procedure Unlock;
    property Current: TArrayOfT read FArray;
  end;

  { TWorkStealingQueue }

  THREADING_GENERIC TWorkStealingQueue<T> = class
  Private
    Type
      TItemList = THREADING_SPECIALIZE TList<T>;
  Private
    FItems : TItemList;
    FLock : TSpinLock;
    FEvent : TEvent;
    function GetCount: Integer;
    function GetIsEmpty: Boolean;
  protected
    procedure Lock;
    procedure UnLock;
  public
    constructor Create;
    destructor Destroy; override;
    function LocalFindAndRemove(const aItem: T): Boolean;
    procedure LocalPush(const aItem: T);
    function LocalPop(out aItem: T): Boolean;
    function TrySteal(out aItem: T; aTimeout: Cardinal = 0): Boolean;
    function Remove(const aItem: T): Boolean;
    property IsEmpty: Boolean read GetIsEmpty;
    property Count: Integer read GetCount;
  end;

  { TObjectCache }

  TObjectCache = class
  Private
    FStack :{$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Contnrs.TStack;
    FLock : TSpinLock;
    FItemClass : TClass;
  public const
    CObjectCacheLimit = 50;
  public
    constructor Create(aClass: TClass);
    destructor Destroy; override;
    procedure Clear;
    function Insert(Instance: Pointer): Boolean;
    function Remove: Pointer;
    function Count : Integer;
  end;

  { TObjectCaches }

  TObjectCaches = class(THREADING_SPECIALIZE TObjectDictionary<TClass, TObjectCache>)
  public
    procedure AddObjectCache(aClass: TClass);
  end;

  { TThreadPool }

  TThreadPool = class sealed
  public type
    // Initial:  -1
    // Execute: 0
    // Cancel >0
    IControlFlag = interface(IInterface)
      function Increment: Integer;
      function Value: Integer;
    end;
    TProcThread = THREADING_SPECIALIZE TProc<TThread>;
  private
    class var FDefaultPool: TThreadPool;
    const
      MinCPUUsage  = 80;        // CPU usage % below which we add threads.
      NumCPUUsageSamples = 10;  // Number of samples for average CPU usage
      MaxThreadsPerCPU = 2;     // Max threads per CPU, used to determine MaxThreads.
      ThreadToRequestRatio = 8; // Number of requests per thread.
      IdleTimeout = 40 * 1000;  // Idle timeout
      MonitorThreadDelay = 500; // Delay between ticks
      MonitorMaxInactiveInterval = 30 * 1000; //
      MonitorIdleLimit = MonitorMaxInactiveInterval div MonitorThreadDelay;
      EnoughThreadsTimeout = 2 * IdleTimeout; // If there are enough threads, if the current thread will wait longer than this, kill it.
      NoRequestsTimeOut = 4 * IdleTimeout; // If there are no requests, if the current thread will wait longer than this, kill it.
    function GrowPool: Boolean;
    function IsThrottledDelay(aLastCreationTick: UInt64; aThreadCount: Cardinal): Boolean;
    procedure LockQueue;
    procedure UnLockQueue;
    procedure WaitForThreads;
    procedure WorkQueued;
    procedure SetMaxLimit(aValue: Integer);
    procedure SetMinLimit(aValue: Integer);
  Private
    FInteractive: Boolean;
    FOnThreadStart: TProcThread;
    FOnThreadTerminate: TProcThread;
    FUnlimitedWorkerThreadsWhenBlocked: Boolean;
    FMaxThreads: Integer; // Maximum number of worker threads.
    FMinThreads: Integer; // Minimum number of worker threads.
    FThreadCount : Integer;  // Number of worker threads
    FIdleThreads : Integer;  // number of worker threads in idle state
    FCPUUsage : Integer;     // CPU usage in %
    FAvgCPUUsage : Integer;  // Average CPU usage in %
    FRequestCount : Integer; // Number of work items in queue
    FPreviousRequestCount : Integer; // Requests when the monitor last added threads: it adds more only for a queue not shorter
    FThreadCreationAt : Int64; // Tick at which the last thread was created.
    FMonitorEvent : TEvent;  // Wakes the monitor when a producer found every allowed worker busy.
    FQueueLock : TSpinlock;
    FQueueSemaphore : TSemaphore; // Work notifications retained until a worker waits.
    FCPUInfo: TThread.TSystemTimes;
    FCpuUsageArray: array[0..TThreadPool.NumCPUUsageSamples - 1] of Cardinal;
    FCurUsageSlot: Integer;

    class function GetCurrentThreadPool: TThreadPool; static;
  protected type

    { IThreadPoolWorkItem }

    IThreadPoolWorkItem = interface(IInterface)
      function ShouldExecute: Boolean;
      procedure ExecuteWork;
    end;

    { TControlFlag }

    TControlFlag = class(TInterfacedObject, IControlFlag)
    Private
      FFlag : Integer;
    public
      function Increment: Integer;
      function Value: Integer;
      constructor Create; overload;
    end;

    { TAbstractWorkerData }

    TAbstractWorkerData = class(TInterfacedObject)
    protected
      FControlFlag: IControlFlag;
      function ShouldExecute: Boolean; virtual;
    public
      class function NewInstance: TObject; override;
      procedure FreeInstance; override;
      constructor Create(aFlag : IControlFlag);
    end;

    { TWorkerData }

    TWorkerData = class(TAbstractWorkerData, IThreadPoolWorkItem)
    protected
      FSender: TObject;
      FWorkerEvent: TNotifyEvent;
      FProc: TProcRef;
      procedure ExecuteWork;
    Public
      constructor Create(aFlag : IControlFlag; aSender : TObject; aEvent : TNotifyEvent);
      constructor Create(aFlag : IControlFlag; aProc: TProcRef);
    end;

    TLightweightEvent = TEvent;

    { TBaseWorkerThread }

    TBaseWorkerThread = class(TThread)
    private
      FThreadPool: TThreadPool;
      FRunningEvent: TLightweightEvent;
      FMyWorkerID : Integer;
    class var FWorkerID : Integer;
    protected
      class function NextWorkerID : Integer;
      function GetWorkerThreadName: string;
      procedure RemoveFromPool;
      procedure SafeTerminate;
      procedure TerminatedSet; override;
      procedure Execute; override;
      property ThreadPool: TThreadPool read FThreadPool;
      property RunningEvent: TLightweightEvent read FRunningEvent;
      property MyWorkerID : Integer Write FMyWorkerID;
    public
      constructor Create(aThreadPool: TThreadPool);
      destructor Destroy; override;
      procedure BeforeDestruction; override;
    end;
    TBaseWorkerThreadList = THREADING_SPECIALIZE TThreadList<TBaseWorkerThread>;

    { TQueueWorkerThread }

    Type
      TWorkStealingQueueThreadPoolWorkItem =  THREADING_SPECIALIZE TWorkStealingQueue<IThreadPoolWorkItem>;

    TQueueWorkerThread = class(TBaseWorkerThread)
    Protected
    const
      MaxCheckWaitTime = MaxInt div 2;
    private
      FCheckWaitTime : Integer;
      FIdle: Boolean;
      FWorkQueue: TWorkStealingQueueThreadPoolWorkItem;
      FWorkException : Exception;
      procedure AdjustWaitTime;
      procedure WrapExecute(var aItem: IThreadPoolWorkItem);
    protected
      procedure ExecuteWorkItem(var aItem: IThreadPoolWorkItem);
      procedure Execute; override;
      property WorkQueue: TWorkStealingQueueThreadPoolWorkItem read FWorkQueue;
      Property CheckWaitTime : Integer Read FCheckWaitTime;
    public
      constructor Create(aThreadPool: TThreadPool);
      destructor Destroy; override;
      property Idle : Boolean Read FIdle Write FIdle;
    end;

    { TThreadPoolMonitor }

    TThreadPoolMonitor = class(TThread)
    private
      FThreadPool : TThreadPool;
      function GetThreadName: string;
    protected
      procedure Execute; override;
    public
      constructor Create(aThreadPool: TThreadPool);
    end;

  private
    const
      MonitorNone    = 0;
      MonitorCreated = 1;

    Type
      TWorkStealingQueueThreadPoolWorkItemArray = THREADING_SPECIALIZE TSparseArray<TWorkStealingQueueThreadPoolWorkItem>;
      // The global work queue must retain a reference to the queued items. A raw
      // pointer queue (Contnrs.TQueue) does not, so a work item could be destroyed
      // while still enqueued, leading to a use-after-free on the worker threads.
      TWorkItemQueue = THREADING_SPECIALIZE TQueue<IThreadPoolWorkItem>;
      TMonitorResult = (mrTerminate,mrContinue,mrIdle);
    var
      FWorkQueue : TWorkItemQueue;
      FQueues : TWorkStealingQueueThreadPoolWorkItemArray;
      FThreads: TBaseWorkerThreadList;

      FMonitorStatus : Integer;
      FShutDown : Boolean;
    procedure NewThread(aThread : TBaseWorkerThread);
    procedure RemoveThread(aThread : TBaseWorkerThread);
  protected
    class threadvar QueueThread : TQueueWorkerThread;
    class var Caches : TObjectCaches;
    // Queue management.
    procedure RegisterWorkerThread(aThread: TQueueWorkerThread);
    procedure UnRegisterWorkerThread(aThread: TQueueWorkerThread);
    // Adding/Removing work
    function DoRemoveWorkItem(WorkerData: IThreadPoolWorkItem): Boolean;
    procedure DoQueueWorkItem(WorkerData: IThreadPoolWorkItem; PreferThread : TQueueWorkerThread);
    procedure AssignWorkToLocalQueue(WorkerData: IThreadPoolWorkItem; aThread: TQueueWorkerThread);
    procedure AssignWorkToGlobalQueue(WorkerData: IThreadPoolWorkItem);
    // Getting work.
    function GetWorkItemForThread(aThread: TQueueWorkerThread; out Itm: IThreadPoolWorkItem): Boolean;
    function GetWorkItemFromQueues(aSkip: TWorkStealingQueueThreadPoolWorkItem; out Itm: IThreadPoolWorkItem): Boolean;
    // Notification when work was queued
    procedure SignalExecuting(aThread: TQueueWorkerThread);
    // Monitoring & Thread management
    procedure CreateMonitorThread;
    procedure WaitForMonitorThread;
    procedure InitCPUStats;
    procedure StopCPUStats;
    function DoMonitor: TMonitorResult;
    function HaveNoWorkers: boolean;
    Procedure GrowIfStarved;
    function AddThreadToPool: TQueueWorkerThread;
  public
    constructor Create;
    destructor Destroy; override;

    class function NewControlFlag: IControlFlag; static;
    procedure QueueWorkItem(aSender: TObject; aWorkerEvent: TNotifyEvent; const aControlFlag: IControlFlag = nil); overload;
    procedure QueueWorkItem(const aWorkerEvent: TProcRef; const aControlFlag: IControlFlag = nil); overload;
    // Return true if new value was actually set.
    function SetMaxWorkerThreads(aValue: Integer): Boolean;
    function SetMinWorkerThreads(aValue: Integer): Boolean;
    property MaxWorkerThreads: Integer read FMaxThreads write SetMaxLimit;
    property MinWorkerThreads: Integer read FMinThreads write SetMinLimit;
    property UnlimitedWorkerThreadsWhenBlocked: Boolean read FUnlimitedWorkerThreadsWhenBlocked  write FUnlimitedWorkerThreadsWhenBlocked default True;
    // if set, then wait loops will call checksynchronize if they are executed in main thread.
    property Interactive: Boolean read FInteractive write FInteractive default False;
    property OnThreadStart: TProcThread read FOnThreadStart write FOnThreadStart;
    property OnThreadTerminate: TProcThread read FOnThreadTerminate write FOnThreadTerminate;
    class property Default: TThreadPool read FDefaultPool;
    class property Current: TThreadPool read GetCurrentThreadPool;
  end;

  { TThreadPoolStats }

  TThreadPoolStats = record
  private
    FWorkerThreadCount: Integer;
    FMinLimitWorkerThreadCount: Integer;
    FMaxLimitWorkerThreadCount: Integer;
    FIdleWorkerThreadCount: Integer;
    FQueuedRequestCount: Integer;
    FRetiredWorkerThreadCount: Integer;
    FAverageCPUUsage: Integer;
    FCurrentCPUUsage: Integer;
    FThreadSuspended: Integer;
    FLastSuspendTick: UInt64;
    FLastThreadCreationTick: UInt64;
    FLastQueuedRequestCount: Integer;
    class function GetCurrent: TThreadPoolStats; static; inline;
    class function GetDefault: TThreadPoolStats; static; inline;
  public
    procedure Assign(const aPool: TThreadPool);
    property WorkerThreadCount: Integer read FWorkerThreadCount;
    property MinLimitWorkerThreadCount: Integer read FMinLimitWorkerThreadCount;
    property MaxLimitWorkerThreadCount: Integer read FMaxLimitWorkerThreadCount;
    property IdleWorkerThreadCount: Integer read FIdleWorkerThreadCount;
    property QueuedRequestCount: Integer read FQueuedRequestCount;
    property RetiredWorkerThreadCount: Integer read FRetiredWorkerThreadCount;
    property AverageCPUUsage: Integer read FAverageCPUUsage;
    property CurrentCPUUsage: Integer read FCurrentCPUUsage;
    property ThreadSuspended: Integer read FThreadSuspended;
    property LastSuspendTick: UInt64 read FLastSuspendTick;
    property LastThreadCreationTick: UInt64 read FLastThreadCreationTick;
    property LastQueuedRequestCount: Integer read FLastQueuedRequestCount;
    class function Get(const aPool: TThreadPool): TThreadPoolStats; static;
    class property Current: TThreadPoolStats read GetCurrent;
    class property Default: TThreadPoolStats read GetDefault;
  end;

  TTaskStatus = (Created, WaitingToRun, Running, Completed, WaitingForChildren, Canceled, Exception);

  ITask = interface (TThreadPool.IThreadPoolWorkItem) ['{AD752DA0-556C-41B5-96F2-0B0CA932E364}']
    function Wait(aTimeout: Cardinal = INFINITE): Boolean; overload;
    function Wait(const aTimeout: TTimeSpan): Boolean; overload;
    procedure Cancel;
    procedure CheckCanceled;
    function Start: ITask;
    function GetStatus: TTaskStatus;
    function GetId: Integer;
    property Id: Integer read GetId;
    property Status: TTaskStatus read GetStatus;
  end;
  TITaskArray = array of ITask;
  TITaskProc = THREADING_SPECIALIZE TProc<ITask>;
  TITaskProcArray = Array of TITaskProc;

  THREADING_GENERIC IFuture<T> = interface(ITask)
    function StartFuture: THREADING_SPECIALIZE IFuture<T>; overload;
    function GetValue: T;
    property Value: T read GetValue;
  end;

  TTaskArray = Array of TTask;

  TAbstractTask = class(TThreadPool.TAbstractWorkerData)
  protected
    type
    IInternalTask = interface(ITask) ['{4C5EFFA7-FB5F-4C38-3E20-84FF25678812}']  
      procedure AddCompleteEvent(const aProc: TITaskProc);
      procedure HandleChildCompletion(const aTask: IInternalTask);
      procedure HandleChildCompletion(const aTask: TTask);
      procedure SetExceptionObject(const aException: TObject);
      procedure RemoveCompleteEvent(const aProc: TITaskProc);
      function GetControlFlag: TThreadPool.IControlFlag;
    end;
  end;

  { TTask }

  TTask = class(TAbstractTask, TThreadPool.IThreadPoolWorkItem, ITask, TAbstractTask.IInternalTask)
  private
    class var FNextTaskID : integer;
    class threadvar _CurrentTask : TTask;

  protected
    type
      TOptionStateFlag = (Started, CallbackRun, ChildWait, Complete, Canceled, Faulted, Replicating, Replica, Raised, Destroying);
      TOptionStateFlags = set of TOptionStateFlag;
      TCreateFlag = (Replicating, Replica);
      TCreateFlags = set of TCreateFlag;
    const
      StateFlagMask = [TOptionStateFlag.Started, TOptionStateFlag.CallbackRun, TOptionStateFlag.ChildWait,
                       TOptionStateFlag.Complete, TOptionStateFlag.Canceled, TOptionStateFlag.Faulted];
      OptionFlagMask = [TOptionStateFlag.Replicating, TOptionStateFlag.Replica];
      ReplicatingStates = OptionFlagMask;
      CompleteStates = [TOptionStateFlag.Destroying, TOptionStateFlag.Complete,
        TOptionStateFlag.Faulted];
      CanceledStates = [TOptionStateFlag.Canceled, TOptionStateFlag.Faulted];

  Public
    Type

      { TTaskParams }

      TTaskParams = record
        Sender: TObject;
        Event: TNotifyEvent;
        Proc: TProcRef;
        Pool: TThreadPool;
        Parent: TTask;
        CreateFlags: TCreateFlags;
        ParentControlFlag: TThreadPool.IControlFlag;
        Procedure ResolvePool;
      end;

  Private
    // Instance stuff
    FStateFlags : TOptionStateFlags;
    FReplicaRoot : TTask;
    FStatus : TTaskStatus;
    FParams : TTaskParams;
    FTaskID : Integer;
    FSubTasks : Integer;
    FStateLock : TSpinLock;
    FTasksWithExceptions : Array of TTask;
    FCompletedEvents : TITaskProcArray;
    FCompletedEventCount : Integer;
    function GetDoneEvent: TLightweightEvent;
  protected
    FException: TObject;
    FDoneEvent : TLightweightEvent;
    function UpdateStateAtomic(aNewState: TOptionStateFlags; aInvalidStates: TOptionStateFlags): Boolean; overload;
    function UpdateStateAtomic(aNewState: TOptionStateFlags; aInvalidStates: TOptionStateFlags; out aOldState: TOptionStateFlags): Boolean; overload;
    procedure SetTaskStop;
    function ShouldCreateReplica: Boolean; virtual;
    function CreateReplicaTask(const aProc: TProcRef; aParent: TTask; aCreateFlags: TCreateFlags; const aParentControlFlag: TThreadPool.IControlFlag): TTask; virtual;
    function CreateReplicaTask(const aParams : TTaskParams) : TTask; virtual;
    procedure CheckFaulted;
    procedure SetComplete;
    procedure AddChild;
    procedure ForgetChild;
    Procedure LockState; inline;
    Procedure UnLockState; inline;
    function InternalExecuteNow: Boolean;
    function GetExceptionObject: Exception;
    function GetIsComplete: Boolean; inline;
    function GetIsReplicating: Boolean; inline;
    function GetHasExceptions: Boolean; inline;
    function GetIsCanceled: Boolean; inline;
    function GetIsQueued: Boolean; inline;
    function GetWasExceptionRaised: Boolean; inline;
    procedure QueueEvents; virtual;
    procedure Complete(UserEventRan: Boolean);
    procedure IntermediateCompletion;
    procedure FinalCompletion;
    procedure ProcessCompleteEvents; virtual;
    procedure SetRaisedState;
    procedure CalcStatus;
    procedure ForceStateFlags(aFlags : TOptionStateFlags); inline;
    function InternalWork: Boolean;
    procedure InternalExecute(var aCurrentTaskVar: TTask);
    procedure Execute;
    procedure DoCancel(aDestroying: Boolean);
    procedure ReplicaCallUserCode;
    procedure ExecuteReplicates(const aRoot: TTask);
    procedure CallUserCode; inline;
    procedure HandleException(const aChildTask: ITask; const aException: TObject);
    procedure HandleException(const aChildTask: TTask; const aException: TObject);
    function MarkAsStarted: Boolean;
    function TryExecuteNow(aWasQueued: Boolean): Boolean;
    { IThreadPoolWorkItem }
    function ShouldExecute: Boolean; override;
    procedure ExecuteWork;
    { ITask }
    function Wait(aTimeout: Cardinal = INFINITE): Boolean; overload;
    function Wait(const aTimeout: TTimeSpan): Boolean; overload;
    procedure Cancel;
    procedure CheckCanceled;
    function Start: ITask;
    function GetId: Integer;
    function GetStatus: TTaskStatus;
    { IInternalTask }
    procedure AddCompleteEvent(const aProc: TITaskProc);
    procedure HandleChildCompletion(const aTask: TAbstractTask.IInternalTask);
    procedure HandleChildCompletion(const aTask: TTask);
    procedure SetExceptionObject(const aException: TObject);
    procedure RemoveCompleteEvent(const aProc: TITaskProc);
    function GetControlFlag: TThreadPool.IControlFlag;
    Property ID : Integer Read GetID;
    property IsComplete: Boolean read GetIsComplete;
    property IsReplicating: Boolean read GetIsReplicating;
    property HasExceptions: Boolean read GetHasExceptions;
    property IsCanceled: Boolean read GetIsCanceled;
    property IsQueued: Boolean read GetIsQueued;
    property WasExceptionRaised: Boolean read GetWasExceptionRaised;
    property DoneEvent: TLightweightEvent read GetDoneEvent;
    property ThreadPool: TThreadPool read FParams.Pool;
    class function DoWaitForAll(const aTasks: array of ITask; aTimeout: Cardinal): Boolean; static;
    class function DoWaitForAny(const aTasks: array of ITask; aTimeout: Cardinal): Integer; static;
    class function TimespanToMilliseconds(const aTimeout: TTimeSpan): Cardinal; static;
    class function NewId: Integer; static;
  Public
  public
    class function CurrentTask: ITask; static;
    constructor Create(const aParams : TTaskParams); overload;
    constructor Create; overload;
    destructor Destroy; override;
    class function Create(aSender: TObject; aEvent: TNotifyEvent): ITask; overload; static;
    class function Create(const aProc: TProcRef): ITask; overload; static;
    class function Create(aSender: TObject; aEvent: TNotifyEvent; const aPool: TThreadPool): ITask; overload; static;
    class function Create(const aProc: TProcref; aPool: TThreadPool): ITask; overload; static;
    THREADING_GENERIC class function Future<T>(aSender: TObject; aEvent: THREADING_SPECIALIZE TFunctionEvent<T>): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;
    THREADING_GENERIC class function Future<T>(aSender: TObject; aEvent: THREADING_SPECIALIZE TFunctionEvent<T>; aPool: TThreadPool): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;
    THREADING_GENERIC class function Future<T>(const aFunc: THREADING_SPECIALIZE TFunc<T>): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;
    THREADING_GENERIC class function Future<T>(const aFunc: THREADING_SPECIALIZE TFunc<T>; aPool: TThreadPool): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;
    class function Run(aSender: TObject; aEvent: TNotifyEvent): ITask; overload; static; inline;
    class function Run(aSender: TObject; aEvent: TNotifyEvent; aPool: TThreadPool): ITask; overload; static; inline;
    class function Run(const aFunc: TProcRef): ITask; overload; static; inline;
    class function Run(const aFunc: TProcRef; aPool: TThreadPool): ITask; overload; static; inline;
    class function WaitForAll(const aTasks: array of ITask): Boolean; overload; static;
    class function WaitForAll(const aTasks: array of ITask; aTimeout: Cardinal): Boolean; overload; static;
    class function WaitForAll(const aTasks: array of ITask; const aTimeout: TTimeSpan): Boolean; overload; static;
    class function WaitForAny(const aTasks: array of ITask): Integer; overload; static;
    class function WaitForAny(const aTasks: array of ITask; aTimeout: Cardinal): Integer; overload; static;
    class function WaitForAny(const aTasks: array of ITask; const aTimeout: TTimeSpan): Integer; overload; static;
  end;

  { TFuture }

  THREADING_GENERIC TFuture<T> = class sealed(TTask, THREADING_SPECIALIZE IFuture<T>)
  Type
    TFunctionEventT = THREADING_SPECIALIZE TFunctionEvent<T>;
    TFunctionRefT = THREADING_SPECIALIZE TFunc<T>;
  Var
    FResult : T;
    FFuncRef : TFunctionRefT;
    FFuncEvent : TFunctionEventT;
    procedure RunFunc(Sender: TObject);
  Protected
    function StartFuture: THREADING_SPECIALIZE IFuture<T>;
    function GetValue: T;
  Public
    constructor Create(aSender: TObject; aEvent: TFunctionEventT; const aFunc: TFunctionRefT; aPool: TThreadPool); overload;
  end;

  { TParallel }

  TParallel = class sealed
  public type
    {$MinEnumSize 4}
    TLoopStateFlag = (Exception, Broken, Stopped, Cancelled);
    TLoopStateFlagSet = Set of TLoopStateFlag;
    {$MinEnumSize default}
    const
      ShouldExitFlags = [TLoopStateFlag.Exception, TLoopStateFlag.Stopped, TLoopStateFlag.Cancelled];

    { TLoopState }
  type
    TLoopState = Class;
    TLoopState32 = Class;
    {$IFDEF THREAD64BIT}
    TLoopState64 = Class;
    {$ENDIF}

    TIteratorEvent32 = procedure (aSender: TObject; aIndex: Integer) of object;
    TIteratorStateEvent32 = procedure (aSender: TObject; aIndex: Integer; const aLoopState: TLoopState) of object;
    TIteratorEvent64 = procedure (aSender: TObject; aIndex: Int64) of object;
    TIteratorStateEvent64 = procedure (aSender: TObject; aIndex: Int64; const aLoopState: TLoopState) of object;
    TIteratorEvent = TIteratorEvent32;
    TIteratorStateEvent = TIteratorStateEvent32;
    TInt32LoopStateProc = THREADING_SPECIALIZE THREADING_PROC2<Integer, TLoopState>;
    TInt32Proc = THREADING_SPECIALIZE TProc<Integer>;
    TInt64LoopStateProc = THREADING_SPECIALIZE THREADING_PROC2<Int64, TLoopState>;
    TInt64Proc = THREADING_SPECIALIZE TProc<Int64>;

    // Global, for the whole loop

    { TInt32LoopProc }

    TInt32LoopProc = Record
      Sender : TObject;
      Event : TIteratorEvent32;
      Proc: TInt32Proc;
      StateEvent: TIteratorStateEvent32;
      ProcWithState: TInt32LoopStateProc;
      LowInclusive,
      HighExclusive,
      Index,
      Stride: Integer;
      Procedure Execute(Iteration : Integer; aState: TLoopState32);
      Function NumTasks : Integer;
      class function create(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent32) : TParallel.TInt32LoopProc; static;
      class function create(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TInt32Proc) : TParallel.TInt32LoopProc; static;
      class function create(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent32) : TParallel.TInt32LoopProc; static;
      class function create(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TInt32LoopStateProc) : TParallel.TInt32LoopProc; static;
      function ToString : String;
    end;

    {$IFDEF THREAD64BIT}

    { TInt64LoopProc }

    TInt64LoopProc = Record
      Sender : TObject;
      Event : TIteratorEvent64;
      Proc: TInt64Proc;
      StateEvent: TIteratorStateEvent64;
      ProcWithState: TInt64LoopStateProc;
      LowInclusive,
      HighExclusive,
      Index,
      Stride: Int64;
      Procedure Execute(Iteration : Int64; aState: TLoopState64);
      Function NumTasks : Integer;
      class function create(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64) : TParallel.TInt64LoopProc; static;
      class function create(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TInt64Proc) : TParallel.TInt64LoopProc; static;
      class function create(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64) : TParallel.TInt64LoopProc; static;
      class function create(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TInt64LoopStateProc) : TParallel.TInt64LoopProc; static;
      function ToString : String;
    end;

    {$ENDIF}

    { ILoopParams }

    ILoopParams = Interface
      procedure CreateRootTask(aParams : TTask.TTaskParams; aCount : Integer);
      procedure ClearRootTask;
      procedure HandleException;
      Function StartLoop : ITask;
    end;

    { TLoopParams }

    TLoopParams = Class(TInterfacedObject,ILoopParams{$ifndef inlazide},TProcRef{$ENDIF})
    private
      Errors : TExceptionArray;
      ErrorCount : Integer;
      StateFlags : TLoopStateFlagSet;
      FStateLock : TSpinLock;
      FStrideCount : Integer;
      FNextStrideAt : Integer;
      FRootTask: ITask;
    public
      Constructor Create;
      Destructor Destroy; override;
      procedure Lock;
      procedure UnLock;
      Procedure HandleException(O : TObject);
      procedure HandleException; overload;
      Function GetBreakAt : Variant; virtual; abstract;
      Procedure Stop;
      Function StartLoop : ITask;
      procedure CreateRootTask(aParams : TTask.TTaskParams; aCount : Integer);
      procedure ClearRootTask;
      // We use the fact that in FPC a reference to procedure is an Interface.
      // Invoke is the method of the interface that is called...
      Procedure Invoke; virtual; abstract;
      function Break : Boolean;
      Function Stopped : Boolean;
      Function Faulted : Boolean;
      Property BreakAt : Variant Read GetBreakAt;
    end;

    // Global, for all tasks in the loop

    { IInt32LoopParams }

    TInt32LoopParams = Class (TLoopParams)
    Private
      FFinalFlags : TLoopStateFlagSet;
      FLoopProc : TInt32LoopProc;
      FBreakAt : Integer;
      FMaxStride : Integer;
      Procedure UpdateBreakAt(aValue : Integer);
      Function GetCurrentStride : Integer;
      Function GetCurrentStart(out aStride: Integer) : Integer;
      Function GetNextStride : Integer;
      function ShouldExitLoop(CurrentIter: Integer): Boolean; overload;
      function ShouldExitLoop: Boolean; inline; overload;
    Public
      Constructor Create(aLoopProc : TInt32LoopProc);
      destructor Destroy; override;
      Function GetBreakAt : Variant; override;
      procedure Invoke; override;
      Property Stride : Integer Read FLoopProc.Stride;
      Property HighExclusive : Integer Read FLoopProc.HighExclusive;
      Property LowExclusive : Integer Read FLoopProc.LowInclusive;
      Property Index : Integer Read FLoopProc.Index;
    end;

    { IInt64LoopParams }
    {$IFDEF THREAD64BIT}
    TInt64LoopParams = Class (TLoopParams)
    Private
      FFinalFlags : TLoopStateFlagSet;
      FLoopProc : TInt64LoopProc;
      FBreakAt : Int64;
      FMaxStride : Int64;
      Procedure UpdateBreakAt(aValue : Int64);
      Function GetCurrentStride : Int64;
      Function GetCurrentStart(out aStride: Int64) : Int64;
      Function GetNextStride : int64;
      function ShouldExitLoop(CurrentIter: Int64): Boolean; overload;
      function ShouldExitLoop: Boolean; inline; overload;
    Public
      Constructor Create(aLoopProc : TInt64LoopProc);
      destructor Destroy; override;
      Function GetBreakAt : Variant; override;
      procedure Invoke; override;
      Property Stride : Int64 Read FLoopProc.Stride;
      Property HighExclusive : Int64 Read FLoopProc.HighExclusive;
      Property LowExclusive : Int64 Read FLoopProc.LowInclusive;
      Property Index : Int64 Read FLoopProc.Index;
    end;
    {$ENDIF}


    // Local, per task
    TLoopState = class
    Private
      FLoopParams : TLoopParams;
    protected
      Type
        TLoopStateFlag = TLoopParams;

    protected
      function GetStopped: Boolean; inline;
      function GetFaulted: Boolean; inline;
      function GetLowestBreakIteration: Variant; inline;
      procedure DoBreak; virtual; abstract;

      function DoShouldExit: Boolean; virtual; abstract;
      function DoGetLowestBreakIteration: Variant; virtual;
    public
      constructor Create(LoopParams : TLoopStateFlag);
      procedure Break;
      procedure Stop;
      function ShouldExit: Boolean;

      property Faulted: Boolean read GetFaulted;
      property Stopped: Boolean read GetStopped;
      property LowestBreakIteration: Variant read GetLowestBreakIteration;
    end;

    // Local, per task

    { TLoopState32 }

    TLoopState32 = Class(TLoopState)
    private
      FCurrentIteration: Integer;
    Public
      Constructor Create(aParams: TInt32LoopParams);
      procedure DoBreak; override;
      function DoShouldExit: Boolean; override;
      Property CurrentIteration : Integer read FCurrentIteration Write FCurrentIteration;
    end;

    { TLoopState64 }

    {$IFDEF THREAD64BIT}
    TLoopState64 = Class(TLoopState)
    private
      FCurrentIteration: Int64;
    Public
      Constructor Create(aParams: TInt64LoopParams);
      procedure DoBreak; override;
      function DoShouldExit: Boolean; override;
      Property CurrentIteration : Int64 read FCurrentIteration Write FCurrentIteration;
    end;
    {$ENDIF}

    { TLoopResult }

    TLoopResult = record
    private
      FCompleted: Boolean;
      FLowestBreakIteration: Variant;
    public
      class function Create : TLoopResult; static;
      property Completed: Boolean read FCompleted;
      property LowestBreakIteration: Variant read FLowestBreakIteration;
    end;


  private
    class function Parallelize32(aLoop: TInt32LoopProc; aPool: TThreadPool): TLoopResult;
    {$IFDEF THREAD64BIT}
    class function Parallelize64(aLoop: TInt64LoopProc; aPool: TThreadPool): TLoopResult;
    {$ENDIF}
  public
    Type
      TProcInteger = THREADING_SPECIALIZE TProc<Integer>;
      TProcIntegerLoopState = THREADING_SPECIALIZE THREADING_PROC2<Integer,TLoopState>;
      TProcInt64 = THREADING_SPECIALIZE TProc<Int64>;
      TProcInt64LoopState = THREADING_SPECIALIZE THREADING_PROC2<Int64,TLoopState>;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState; aPool: TThreadPool): TLoopResult; overload; static; inline;
    {$IFDEF THREAD64BIT}
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64): TLoopResult; overload; static; inline;
    class function &For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState): TLoopResult; overload; static; inline;
    class function &For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64; aPool: TThreadPool): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState): TLoopResult; overload; static; inline;
    class function &For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState; aPool: TThreadPool): TLoopResult; overload; static; inline;
    {$ENDIF}
    class function Join(aSender: TObject; aEvents: array of TNotifyEvent): ITask; overload; static;
    class function Join(aSender: TObject; aEvents: array of TNotifyEvent; aPool: TThreadPool): ITask; overload; static;
    class function Join(aSender: TObject; aEvent1, aEvent2: TNotifyEvent): ITask; overload; static; inline;
    class function Join(aSender: TObject; aEvent1, aEvent2: TNotifyEvent; aPool: TThreadPool): ITask; overload; static;
    class function Join(const aProcs: array of TProcRef): ITask; overload; static;
    class function Join(const aProcs: array of TProcRef; aPool: TThreadPool): ITask; overload; static;
    class function Join(const aProc1, aProc2: TProcRef): ITask; overload; static; inline;
    class function Join(const aProc1, aProc2: TProcRef; aPool: TThreadPool): ITask; overload; static;
  end;

function GetThreadPoolInteractive(APool: TThreadPool): Boolean;
procedure SetThreadPoolInteractive(APool: TThreadPool; AValue: Boolean);

{
  These must be exposed, otherwise they cannot be used inside generic methods :/

  At optimization level 1, the {$IFDEF USE_THREADLOG}ThreadLog is not called at all if the routine is empty.
  So if DEBUGTHREADPOOL is not defined, we must ensure the methods are empty.
  without optimization, the methods are called but will not do anything.
}
{$IFDEF USE_THREADLOG}
procedure ThreadLog(const Method,Msg: string); overload;
procedure ThreadLog(const Method,Fmt: string; Args: array of const); overload;
{$ENDIF}


implementation

uses system.diagnostics;

Resourcestring
  SWorkerThreadName = 'Worker Thread - %s #%d ThreadPool - %p';
  SAggregateException = 'Aggregate exception';
  SOperationCancelled = 'Operation cancelled';
  SCannotStartCompletedTask = 'Cannot start completed task';
  SErrBreakAfterStop = 'Break loop after loop was stopped';
  SErrInvalidTaskConstructor = 'Cannot use parameterless TTask constructor';
  SErrOneOrMoreTasksCancelled = 'One or more tasks where cancelled';
  SErrWaitNilTask = 'Task cannot be nil';
  SErrInvalidTimeout = 'Timeout must be between 0 and 2147483647 milliseconds';
  SAggregateExceptionCount = 'Aggregate exception for %d exceptions';

Type
  TSpinLockHelper = record helper for TSpinLock
    procedure leave;
  end;

procedure TSpinLockHelper.leave;
begin
  Exit;
end;


{$IFDEF USE_THREADLOG}
procedure ThreadLog(const Method,Msg: string); overload;

{$IFDEF DEBUGTHREADPOOL}
var
  TID : String;
{$ENDIF}
begin
{$IFDEF DEBUGTHREADPOOL}
  if TThread.CurrentThread.ThreadID = MainThreadID then
    TID:='Main Thread'
  else
    TID:=IntToStr(PtrInt(TThread.CurrentThread.ThreadID));
  Writeln('[',TID:15,']{',Method,'} ',Msg);
  Flush(output);
{$ENDIF}
end;

procedure ThreadLog(const Method,Fmt: string; Args: array of const); overload;
begin
{$IFDEF DEBUGTHREADPOOL}
  ThreadLog(Method,SafeFormat(Fmt,Args));{}
{$ENDIF}
end;

{$ENDIF USE_THREADLOG}

Function BToS(B : Boolean) : String;
begin
  Result:=BoolToStr(B,True);
end;


function GetThreadPoolInteractive(APool: TThreadPool): Boolean;

begin
  Result:=aPool.FInteractive;
end;

procedure SetThreadPoolInteractive(APool: TThreadPool; AValue: Boolean);

begin
  aPool.FInteractive:=aValue;
end;

{ *********************************************************************
  Private classes, not part of interface.
  *********************************************************************}


Type

  { TReplicableTask }

  TReplicableTask = class(TTask)
  private
    FTaskCount: Integer;
  protected
    function ShouldCreateReplica: Boolean; override;
    function CreateReplicaTask(const aParams : TTaskParams): TTask; override;
  Public
    constructor Create(const aParams : TTaskParams; aTaskCount: Integer); overload;
  end;

  { TReplicatedTask }

  TReplicatedTask = class(TTask)
  end;

  { TProcJoinTask }

  TProcJoinTask = class(TReplicableTask)
    FProc : TParallel.TInt32LoopProc;
    FProcList : array of TProcref;
    constructor Create(const AProcs: array of TProcRef; APool: TThreadPool);
  private
    procedure JoinTasks;
  end;

  { TEventJoinTask }

  TEventJoinTask = class(TReplicableTask)
    FProc : TParallel.TInt32LoopProc;
    FEventList : array of TNotifyEvent;
    constructor Create(Sender: TObject; const AEvents : array of TNotifyEvent; APool: TThreadPool);
  private
    procedure JoinTasks;
  end;


{ *********************************************************************
  TExceptionList
  *********************************************************************}

class function TExceptionList.Create(aCapacity: Integer): TExceptionList;
begin
  Result:=Default(TExceptionList);
  SetLength(Result.List,aCapacity);
  Result.Count:=0;
end;

class function TExceptionList.Create(Initial: Exception; aCapacity: Integer): TExceptionList;
begin
  Result:=Create(aCapacity);
  Result.List[0]:=Initial;
end;

class function TExceptionList.Create(aExceptionArray: array of Exception): TExceptionList;

var
  I,Len : Integer;
begin
  Len:=Length(aExceptionArray);
  Result:=Create(Len+1); // spare
  For I:=0 to Len-1 do
    Result.List[i]:=aExceptionArray[i];
  Result.Count:=Len;
end;

procedure TExceptionList.Flatten(aException : Exception);

var
  lList : TExceptionList;
  I : Integer;
  Agg : EAggregateException absolute aException;

begin
  if Not (aException is EAggregateException) then
    Add(aException)
  else
    begin
    lList:=Agg.Flist;
    Agg.Flist:=TExceptionList.Create(0);
    GrowCapacity(Count+lList.Count);
    For I:=0 to lList.Count-1 do
      Flatten(lList.List[i]);
    end;
end;

procedure TExceptionList.AddFromTask(aTask: TTask);

begin
  if not (aTask.FException is Exception) then
    FreeAndNil(aTask.FException)
  else
    begin
    Flatten(Exception(aTask.FException));
    if aTask.FException is EAggregateException then
      FreeAndNil(aTask.FException)
    else
      aTask.FException:=Nil;
    end;
end;

procedure TExceptionList.Add(aException: Exception);
begin
  If Count=Length(List) then
    SetLength(List,Count+10);
  List[Count]:=aException;
  Inc(Count);
end;

function TExceptionList.GrowCapacity(aMinCapacity: Integer): Integer;
begin
  If aMinCapacity>Length(List) then
    SetLength(List,aMinCapacity);
  Result:=Length(List);
end;

function TExceptionList.Capacity: Integer;
begin
  Result:=Length(List);
end;

function TExceptionList.Truncate: TExceptionArray;
begin
  SetLength(List,Count);
  Result:=List;
end;

procedure TExceptionList.ClearList;
begin
  While Count>0 do
    begin
    Dec(Count);
    FreeAndNil(List[Count]);
    end;
end;

{ *********************************************************************
  EAggregateException
  *********************************************************************}



function EAggregateException.GetInnerException(aIndex: Integer): Exception;
begin
  Result:=Exception(FList.List[aIndex]);
end;

constructor EAggregateException.Create(const aExceptionArray: array of Exception);
begin
  Create(SAggregateException,aExceptionArray);
end;

constructor EAggregateException.Create(const aMessage: string; const aExceptionArray: array of Exception);

begin
  Inherited Create(aMessage);
  Flist:=TExceptionList.Create(aExceptionArray);
end;

Procedure EAggregateException.ClearList;

begin
  FList.ClearList;
end;

destructor EAggregateException.Destroy;
begin
  ClearList;
  inherited Destroy;
end;

function EAggregateException.GetEnumerator: TExceptionEnumerator;
begin
  Result:=TExceptionEnumerator.Create(Self)
end;

procedure EAggregateException.Handle(aExceptionHandlerEvent: TExceptionHandlerEvent);

  procedure DoEvent(const aException: Exception; var aHandled: Boolean);

  begin
    aExceptionHandlerEvent(aException,aHandled);
  end;

begin
  Handle(TExceptionHandlerProc(@DoEvent));
end;

procedure EAggregateException.Handle(const aExceptionHandlerProc: TExceptionHandlerProc);

var
  I : Integer;
  Handled: Boolean;
  E : Exception;
  OurList,Unhandled: TExceptionList;

begin
  OurList:=TExceptionList.Create(Count);
  Unhandled:=TExceptionList.Create(Count);
  for I:=0 to FList.Count-1 do
    begin
    Handled:=False;
    E:=FList.List[i];
    AExceptionHandlerProc(E,Handled);
    if Handled then
      OurList.Add(E)
    else
      UnHandled.Add(E)
    end;
  // In case of an exception during proc, we still own all exceptions.
  if Unhandled.Count>0 then
    begin
    // When we got here, unhandled ones will be owned by new exception.
    // Make sure we still own the handled ones !
    FList:=OurList;
    raise EAggregateException.Create(Message,UnHandled.Truncate);
    end;
end;

procedure EAggregateException.Add(aException: Exception);
begin
  Flist.Add(aException);
end;

function EAggregateException.ToString: RTLString;
var
  S : String;
  I, Len: Integer;
begin
  S:=inherited ToString;
  S:=S+sLineBreak+Format(SAggregateExceptionCount,[Count]);
  Len:=MaxLoggedExceptions;
  if Count<Len then
    Len:=Count;
  for I:=0 to Len-1 do
    S:=S+sLineBreak+Format('#%d %s',[I,InnerExceptions[I].ToString]);
  if Count>Len then
    S:=S+sLineBreak+'...';
  Result:=S;
end;

{ *********************************************************************
  EAggregateException.TExceptionEnumerator
  *********************************************************************}

function EAggregateException.TExceptionEnumerator.GetCurrent: Exception;
begin
  Result:=FException.InnerExceptions[FCurrent];
end;

constructor EAggregateException.TExceptionEnumerator.Create(aException: EAggregateException);
begin
  FException:=aException;
  FCurrent:=-1;
end;

function EAggregateException.TExceptionEnumerator.MoveNext: Boolean;
begin
  if FCurrent>=FException.Count then
    Exit(False);
  Inc(FCurrent);
  Result:=FCurrent<FException.Count;
end;

{ *********************************************************************
  TSparseArray
  *********************************************************************}

constructor TSparseArray THREADING_PARAMS.Create(aInitialSize: Integer);
begin
  FLock:=TSpinLock.Create(False);
  if aInitialSize < 1 then
    aInitialSize:=1;
  SetLength(FArray,aInitialSize);
end;

destructor TSparseArray THREADING_PARAMS.Destroy;
begin
  inherited Destroy;
end;

procedure TSparseArray THREADING_PARAMS.Lock;
begin
  FLock.Enter;
end;

procedure TSparseArray THREADING_PARAMS.Unlock;
begin
  FLock.Exit;
end;

function TSparseArray THREADING_PARAMS.Add(const aItem: T): Integer;

var
  I,Len: Integer;
  Tmp : TArrayOfT;

begin
  Tmp:=Default(TArrayOfT);
  Lock;
  try
    I:=0;
    Len:=Length(FArray);
    While (I<Len) do
      begin
      if Not Assigned(FArray[i]) then
        begin
        FArray[i]:=aItem;
        Exit(I);
        end;
      Inc(I);
      end;
    SetLength(Tmp,Len*2);
    Move(Farray[0],Tmp[0],Len*SizeOf(T));
    FArray:=Tmp;
    FArray[Len]:=aItem;
    Result:=Len;
  finally
    UnLock;
  end;
end;


function TSparseArray THREADING_PARAMS.Remove(const aItem: T): Boolean;

var
  I: Integer;

begin
  Lock;
  try
    I:=Length(FArray)-1;
    While (I>=0) and (FArray[I]<>aItem) do
      Dec(I);
    Result:=(I>=0);
    if Result then
      FArray[I]:=nil;
  finally
    Unlock;
  end;
end;

{ *********************************************************************
  TWorkStealingQueue
  *********************************************************************}


function TWorkStealingQueue THREADING_PARAMS.GetCount: Integer;
begin
  Result:=FItems.Count;
end;

function TWorkStealingQueue THREADING_PARAMS.GetIsEmpty: Boolean;
begin
  Result:=FItems.Count=0;
end;

procedure TWorkStealingQueue THREADING_PARAMS.Lock;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.Lock','Enter %d',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
  try
    FLock.Enter;
  except
    on E : Exception do
	  begin
      {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.Lock','%d Exception: %s %s',[PtrInt(Self),E.ClassName,E.Message]);{$ENDIF USE_THREADLOG}
	  end;
  end;
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.Lock','Leave %d',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
end;

procedure TWorkStealingQueue THREADING_PARAMS.UnLock;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.UnLock','Enter %d',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
  FLock.Exit;
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.UnLock','Leave %d',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
end;

constructor TWorkStealingQueue THREADING_PARAMS.Create;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.Create',IntToStr(PtrInt(Self)));{$ENDIF USE_THREADLOG}
  FItems:=TItemList.Create;
  FLock:=TSpinLock.Create(False);
  FEvent:=TEvent.Create(False);
end;

destructor TWorkStealingQueue THREADING_PARAMS.Destroy;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TWorkStealingQueue.Destroy',IntToStr(PtrInt(Self)));{$ENDIF USE_THREADLOG}
  FreeAndNil(FItems);
  FreeAndNil(FEvent);
  inherited Destroy;
end;

function TWorkStealingQueue THREADING_PARAMS.LocalFindAndRemove(const aItem: T): Boolean;

begin
  Lock;
  try
    Result:=FItems.Remove(aItem)<>-1;
  finally
    UnLock
  end;
end;

procedure TWorkStealingQueue THREADING_PARAMS.LocalPush(const aItem: T);
begin
  Lock;
  try
    FItems.Add(aItem);
    FEvent.SetEvent;
  finally
    UnLock;
  end;
end;

function TWorkStealingQueue THREADING_PARAMS.LocalPop(out aItem: T): Boolean;

begin
  Lock;
  try
    Result:=FItems.Count>0;
    if Result then
      aItem:=FItems.ExtractIndex(FItems.Count-1);
  finally
    UnLock;
  end;
end;

function TWorkStealingQueue THREADING_PARAMS.TrySteal(out aItem: T; aTimeout: Cardinal): Boolean;
begin
  Result:=LocalPop(aItem);
  // Without a timeout there is nothing to wait for: no event calls.
  If Result or (aTimeout=0) then
    exit;
  FEvent.ResetEvent;
  if FEvent.WaitFor(aTimeOut)=wrSignaled then
    Result:=LocalPop(aItem);
  // We can miss one if another thread got the item. Normally we'd need to wait again till timeout is really over.
end;

function TWorkStealingQueue THREADING_PARAMS.Remove(const aItem: T): Boolean;
begin
  Lock;
  try
    Result:=FItems.Remove(aItem)<>-1;
  finally
    UnLock;
  end;
end;

{ *********************************************************************
  TObjectCache
  *********************************************************************}

constructor TObjectCache.Create(aClass: TClass);
begin
  FItemClass:=aClass;
  FStack:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Contnrs.TStack.Create();
  FLock:=TSpinLock.Create(False);
end;

destructor TObjectCache.Destroy;
begin
  Clear;
  FreeAndNil(FStack);
  inherited Destroy;
end;

procedure TObjectCache.Clear;

var
  P : Pointer;

begin
  FLock.Enter;
  try
    P:=FStack.Pop;
    While P<>Nil do
      begin
      FreeMem(P);
      P:=FStack.Pop;
      end;
  finally
    FLock.Exit;
  end;
end;

function TObjectCache.Insert(Instance: Pointer): Boolean;
begin
  FLock.Enter;
  try
    Result:=FStack.Count<CObjectCacheLimit;
    if Result then
      FStack.Push(Instance);
  finally
    FLock.Exit;
  end;
end;

function TObjectCache.Remove: Pointer;

begin
  FLock.Enter;
  try
    Result:=FStack.Pop;
  finally
    FLock.Exit;
  end;
end;

function TObjectCache.Count: Integer;
begin
  Result:=FStack.Count;
end;

{ *********************************************************************
  TObjectCaches
  *********************************************************************}

procedure TObjectCaches.AddObjectCache(aClass: TClass);
begin
  Add(aClass,TObjectCache.Create(aClass));
end;

{ *********************************************************************
  TThreadPool
  *********************************************************************}

class function TThreadPool.GetCurrentThreadPool: TThreadPool; static;

var
  Task: ITask;

begin
  Task:=TTask.CurrentTask;
  if Assigned(Task) then
    Result := (Task as tTask).ThreadPool
  else
    Result := TThreadPool.Default;
end;



procedure TThreadPool.WorkQueued;

var
  DoEventSignal : Boolean;

begin
  // Notify waiting threads.
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.WorkQueued','enter');{$ENDIF USE_THREADLOG}
  AtomicIncrement(FRequestCount);
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.WorkQueued','Queueing work (Requests: %d)',[FRequestCount]);{$ENDIF USE_THREADLOG}
  // Wake an idle worker even when the pending work also calls for growth.
  DoEventSignal:=FIdleThreads>0;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.WorkQueued','DoEventSignal %s',[BToS(DoEventSignal)]);{$ENDIF USE_THREADLOG}
  if DoEventSignal then
    FQueueSemaphore.Release;
  // Nobody is free and no thread may be added: as in Delphi the monitor
  // decides at once whether every worker is blocked.
  if (FIdleThreads<FRequestCount) and not GrowPool and FUnlimitedWorkerThreadsWhenBlocked then
    FMonitorEvent.SetEvent;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.WorkQueued','leave');{$ENDIF USE_THREADLOG}
end;

function TThreadPool.GrowPool: Boolean;

  procedure DoAdd;

  begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool.DoAdd','Enter');{$ENDIF USE_THREADLOG}
    LockQueue;
    try
      AddThreadToPool;
    finally
      UnlockQueue;
      {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool.DoAdd','Leave');{$ENDIF USE_THREADLOG}
    end;
  end;

Var
  NeedMinimum,IdleDeficit,HaveRoom : Boolean;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool','Enter');{$ENDIF USE_THREADLOG}
  NeedMinimum:=(FThreadCount<FMinThreads);
  IdleDeficit:=(FIdleThreads<FRequestCount);
  HaveRoom:=(FThreadCount<FMaxThreads);
  Result:=NeedMinimum or (IdleDeficit and HaveRoom);
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool','DoGrow: %s, NeedMinimum: %s, IdleDeficit: %s, HaveRoom: %s',[BToS(Result),BToS(NeedMinimum),BToS(IdleDeficit),BToS(HaveRoom)]);{$ENDIF USE_THREADLOG}
  if Not Result then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool','Leave (not DoGrow)');{$ENDIF USE_THREADLOG}
    exit;
    end;
  DoAdd;
  while (FThreadCount<FMinThreads) do
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool','Adding thread to pool: %d<%d',[FThreadCount,FMinThreads]);{$ENDIF USE_THREADLOG}
    DoAdd;
    end;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowPool','Leave');{$ENDIF USE_THREADLOG}
end;


procedure TThreadPool.NewThread(aThread: TBaseWorkerThread);
begin
  if Assigned(FThreads) then
    FThreads.Add(aThread);
end;

procedure TThreadPool.RemoveThread(aThread: TBaseWorkerThread);
begin
  AtomicDecrement(FThreadCount);
  // A request may have arrived after the worker's final queue check, while
  // it still occupied the last slot. Reconsider it as soon as that slot opens.
  if not FShutdown and (FRequestCount>0) then
    GrowPool;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.RemoveThread','Thread count now %d',[FThreadCount]);{$ENDIF USE_THREADLOG}
  if assigned(FOnThreadTerminate) then
    FOnThreadTerminate(aThread);
  // Keep the pool alive until the departing worker has finished using it.
  If Assigned(FThreads) then
    FThreads.Remove(aThread);
end;

procedure TThreadPool.AssignWorkToLocalQueue(WorkerData: IThreadPoolWorkItem; aThread: TQueueWorkerThread);

begin
  aThread.WorkQueue.LocalPush(WorkerData);
  WorkQueued;
end;

procedure TThreadPool.AssignWorkToGlobalQueue(WorkerData: IThreadPoolWorkItem);

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.AssignWorkToGlobalQueue','locking queue');{$ENDIF USE_THREADLOG}
  LockQueue;
  try
    FWorkQueue.Enqueue(WorkerData);
  finally
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.AssignWorkToGlobalQueue','unlocking queue');{$ENDIF USE_THREADLOG}
    UnLockQueue;
  end;
  WorkQueued;
end;

procedure TThreadPool.CreateMonitorThread;


var
  Status: Integer;

begin
  Status:=FMonitorStatus;
  if Status<>MonitorNone then
    exit;
  Status:=AtomicCmpExchange(FMonitorStatus, MonitorCreated, MonitorNone);
  if Status=MonitorNone then
    try
      TThreadPoolMonitor.Create(Self);
    except
      AtomicExchange(FMonitorStatus,MonitorNone);
     raise;
    end;
end;

procedure TThreadPool.WaitForMonitorThread;


begin
  While (FMonitorStatus<>MonitorNone) do
    TThread.Sleep(MonitorThreadDelay div 4);
end;

procedure TThreadPool.DoQueueWorkItem(WorkerData: IThreadPoolWorkItem; PreferThread : TQueueWorkerThread);
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.DoQueueWorkItem','enter');{$ENDIF USE_THREADLOG}
  if assigned(PreferThread) and (PreferThread.ThreadPool=Self) then
    AssignWorkToLocalQueue(WorkerData,PreferThread)
  else
    AssignWorkToGlobalQueue(WorkerData);
  if FMonitorStatus = MonitorNone then
    CreateMonitorThread;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.DoQueueWorkItem','leave');{$ENDIF USE_THREADLOG}
end;


constructor TThreadPool.Create;
var
  PC: Integer;

begin
  FMonitorEvent:=TEvent.Create(Nil,True,False,'');
  FQueueSemaphore:=TSemaphore.Create(Nil,0,MaxInt,'');
  FQueueLock:=TSpinLock.Create(False);
  FWorkQueue:=TWorkItemQueue.Create;
  PC:=TThread.ProcessorCount;
  FQueues:=TWorkStealingQueueThreadPoolWorkItemArray.Create(PC);
  FMinThreads:=PC div 4;
  if FMinThreads<2 then
    FMinThreads:=2;
  FMaxThreads:=PC*MaxThreadsPerCPU;
  FUnlimitedWorkerThreadsWhenBlocked:=True;
  FThreads:=TBaseWorkerThreadList.Create;
  FThreads.Duplicates:=dupIgnore;
{
  FThreads := TThreadList<TBaseWorkerThread>.Create;
  FThreads.Duplicates := dupIgnore;
}
end;

procedure TThreadPool.WaitForThreads;

var
  T : TThread;
  List : THREADING_SPECIALIZE TList<TBaseWorkerThread>;
  Empty : Boolean;

begin
  if Not Assigned(FThreads) then
    exit;
  Repeat
    List:=FThreads.LockList;
    try
      Empty:=List.Count=0;
      If not Empty then
        begin
        for T in List do
          begin
          T.Terminate;
          {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.WaitForThreads','Terminated thread');{$ENDIF USE_THREADLOG}
          end;
        // A worker waiting for work wakes with a permit and sees FShutdown.
        FQueueSemaphore.Release(List.Count);
        end;
    finally
      FThreads.UnlockList;
    end;
    if not empty then
      // give threads time to deregister
      Sleep(MonitorThreadDelay div 4);
  Until Empty;
end;


destructor TThreadPool.Destroy;
begin
  FShutdown:=True;
  WaitForThreads;
  WaitForMonitorThread;
  FreeAndNil(FWorkQueue);
  FreeAndNil(FQueues);
  FreeAndNil(FMonitorEvent);
  FreeAndNil(FQueueSemaphore);
  FreeAndNil(FThreads);
  inherited Destroy;
end;

class function TThreadPool.NewControlFlag: IControlFlag;
begin
  Result:=TControlFlag.Create;
end;

procedure TThreadPool.QueueWorkItem(aSender: TObject; aWorkerEvent: TNotifyEvent; const aControlFlag: IControlFlag);

var
  WorkerData: TWorkerData;
  aFlag : IControlFlag;

begin
  aFlag:=aControlFlag;
  if aFlag=Nil then
    aFlag:=NewControlFlag;
  WorkerData:=TWorkerData.Create(aFlag,aSender,aWorkerEvent);
  DoQueueWorkItem(WorkerData,Nil);
end;

procedure TThreadPool.QueueWorkItem(const aWorkerEvent: TProcRef; const aControlFlag: IControlFlag);

var
  WorkerData: TWorkerData;
  aFlag : IControlFlag;

begin
  aFlag:=aControlFlag;
  if aFlag=Nil then
    aFlag:=NewControlFlag;
  WorkerData:=TWorkerData.Create(aFlag,aWorkerEvent);
  DoQueueWorkItem(WorkerData,Nil);
end;

// As in Delphi, each limit is checked on its own: a minimum above the maximum
// makes GrowPool start that many workers at once.
function TThreadPool.SetMaxWorkerThreads(aValue: Integer): Boolean;
begin
  Result:=(aValue>0);
  if Result then
    AtomicExchange(FMaxThreads,aValue);
end;

function TThreadPool.SetMinWorkerThreads(aValue: Integer): Boolean;
begin
  Result:=(aValue>=0);
  if Result then
    AtomicExchange(FMinThreads,aValue);
end;

// The properties write as in Delphi: a refused value leaves the limit as is.
procedure TThreadPool.SetMaxLimit(aValue: Integer);
begin
  SetMaxWorkerThreads(aValue);
end;

procedure TThreadPool.SetMinLimit(aValue: Integer);
begin
  SetMinWorkerThreads(aValue);
end;

procedure TThreadPool.SignalExecuting(aThread : TQueueWorkerThread);

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.SignalExecuting','Enter (Requests left: %d, Idle: %d)',[FRequestCount,FIdleThreads]);{$ENDIF USE_THREADLOG}
  if aThread.Idle then
    AtomicDecrement(FIdleThreads);
  aThread.Idle:=False;
  AtomicDecrement(FRequestCount);
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.SignalExecuting','Leave (Requests left: %d, Idle: %d)',[FRequestCount,FIdleThreads]);{$ENDIF USE_THREADLOG}
end;

procedure TThreadPool.LockQueue;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.LockQueue','Enter');{$ENDIF USE_THREADLOG}
  FQueueLock.Enter;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.LockQueue','Leave');{$ENDIF USE_THREADLOG}
end;

procedure TThreadPool.UnLockQueue;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.UnLockQueue','Enter');{$ENDIF USE_THREADLOG}
  FQueueLock.Leave;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.UnLockQueue','Leave');{$ENDIF USE_THREADLOG}
end;


// Return true if an item was found in one of the queues.
function TThreadPool.GetWorkItemFromQueues(aSkip: TWorkStealingQueueThreadPoolWorkItem; out Itm: IThreadPoolWorkItem): Boolean;

var
  I: integer;
  aQueue : TWorkStealingQueueThreadPoolWorkItem;

begin
  Result:=False;
  FQueues.Lock;
  try
    For I:=0 to Length(FQueues.Current)-1 do
      begin
      aQueue:=FQueues.Current[I];
      if (aQueue<> nil) and (aQueue<>aSkip) and aQueue.TrySteal(Itm) then
       Exit(True);
      end;
  finally
    FQueues.Unlock;
  end;
end;

procedure TThreadPool.RegisterWorkerThread(aThread : TQueueWorkerThread);

begin
  // The parent class already added us in the worker list.
  QueueThread:=aThread;
  FQueues.Add(aThread.WorkQueue);
end;

procedure TThreadPool.UnRegisterWorkerThread(aThread: TQueueWorkerThread);
begin
  FQueues.Remove(aThread.WorkQueue);
  if aThread.Idle then
    begin
    AtomicDecrement(FIdleThreads);
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.UnRegisterWorkerThread','Idle count: %d',[FIdleThreads]);{$ENDIF USE_THREADLOG}
    end;
  QueueThread:=Nil;
end;

function TThreadPool.DoRemoveWorkItem(WorkerData: IThreadPoolWorkItem): Boolean;
begin
  Result:=Assigned(QueueThread) and Assigned(QueueThread.WorkQueue);
  if Not Result then
    exit;
  Result:=QueueThread.WorkQueue.LocalFindAndRemove(WorkerData);
end;

// if there is work, return it in Itm.
// If there is no work, return True if the thread should continue, False if it should terminate.

function TThreadPool.GetWorkItemForThread(aThread: TQueueWorkerThread; out Itm: IThreadPoolWorkItem): Boolean;

  // The global queue first, then the local queues of the other threads.
  function TakeWork: Boolean;
  begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','locking queue');{$ENDIF USE_THREADLOG}
    LockQueue;
    try
      // FWorkQueue access is guarded by LockQueue.
      if (FWorkQueue.Count > 0) then
        Itm:=FWorkQueue.Dequeue;
    finally
      {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','unlocking queue');{$ENDIF USE_THREADLOG}
      UnLockQueue;
    end;
    Result:=Assigned(Itm) or GetWorkItemFromQueues(aThread.WorkQueue,Itm);
  end;

  // A worker leaving the idle set must recheck work published while it
  // still counted, before releasing its slot in RemoveThread.
  function KeepWorking: Boolean;
  begin
    AtomicDecrement(FIdleThreads);
    aThread.Idle:=False;
    Result:=TakeWork;
  end;

Var
  Woken : Boolean;

begin
  Result:=True;
  if FShutDown and (FRequestCount=0) then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Shutting down, no work -> quit');{$ENDIF USE_THREADLOG}
    Exit(False);
    end;
  // Publish idle before the last queue check: a producer either leaves work
  // for that check or observes an idle worker and leaves a semaphore permit.
  if not aThread.Idle then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','marking thread %d as idle',[PtrInt(aThread.ThreadID)]);{$ENDIF USE_THREADLOG}
    AtomicIncrement(FIdleThreads);
    aThread.Idle:=True;
    end;
  if TakeWork then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Got work, -> no quit');{$ENDIF USE_THREADLOG}
    Exit(True); // We got work, do not stop thread
    end;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Waiting for queue semaphore (%d ms.)',[aThread.CheckWaitTime]);{$ENDIF USE_THREADLOG}
  Woken:=FQueueSemaphore.WaitFor(aThread.CheckWaitTime)=wrSignaled;
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Work queued triggered: %s',[BToS(Woken)]);{$ENDIF USE_THREADLOG}
  if FShutdown then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Shutdown -> quit');{$ENDIF USE_THREADLOG}
    Exit(False); // Stop thread
    end;
  if Woken then
    Exit(True); // Work was queued: look for it, the wait was no idle time
  // Nothing to do. Adjust waiting time or stop thread.
  if (FThreadCount > FMinThreads+1) then
    begin
    // The existing threads can handle the work ?
    if (FRequestCount < ThreadToRequestRatio * (FThreadCount-1)) then
      // we already increased wait time sufficiently ?
      begin
      if (aThread.CheckWaitTime>EnoughThreadsTimeOut) then
        begin
        {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','Enough threads to handle workload -> quit');{$ENDIF USE_THREADLOG}
        Exit(KeepWorking); // Stop thread, unless work came meanwhile
        end;
      end;
    aThread.AdjustWaitTime;
    end
  else  if (FRequestCount<=0) then
    // We've got one thread and no requests
    begin
    // if we waited long enough...
    if (aThread.CheckWaitTime>NoRequestsTimeOut) then
      begin
      {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GetWorkItemForThread','One thread, waiting quite long -> quit');{$ENDIF USE_THREADLOG}
      Exit(KeepWorking); // Stop thread, unless work came meanwhile
      end;
    aThread.AdjustWaitTime;
    end;
end;

procedure TThreadPool.InitCPUStats;

begin
  TThread.GetSystemTimes(FCPUInfo);
  FCurUsageSlot:=0;
  FillChar(FCPUUsageArray, SizeOf(FCPUUsageArray), 0);
end;

procedure TThreadPool.StopCPUStats;

begin
  FCurUsageSlot:=0;
  FillChar(FCPUUsageArray, SizeOf(FCPUUsageArray), 0);
end;

function TThreadPool.HaveNoWorkers : boolean;

var
  List: THREADING_SPECIALIZE TList<TBaseWorkerThread>;
  Worker: TBaseWorkerThread;

begin
  Result:=False;
  // A worker clears Idle before removing its request count.
  if FRequestCount<>0 then
    Exit;
  List:=FThreads.LockList;
  try
    for Worker in List do
      if not TQueueWorkerThread(Worker).Idle then
        Exit;
    Result:=True;
  finally
    FThreads.UnlockList;
  end;
end;
function TThreadPool.IsThrottledDelay(aLastCreationTick: UInt64; aThreadCount: Cardinal): Boolean;

begin
  Result:=(GetTickCount64-aLastCreationTick)>1;
  if aThreadCount<>0 then; // Silence compiler warning
end;

// The monitor calls this while the processors are not busy.  Work waits and no
// worker is idle: the workers are blocked, not busy.  As in Delphi, threads are
// added only for a queue not shorter than at the last addition and not in the
// tick of a thread creation: one below the maximum and, when
// UnlimitedWorkerThreadsWhenBlocked is set, up to half the maximum plus one
// above it.
procedure TThreadPool.GrowIfStarved;

var
  Requests,Grow,I: Integer;

begin
  if FRequestCount<=0 then
    Exit;
  LockQueue;
  try
    Requests:=FRequestCount;
    if (Requests<=0) or (Requests<FPreviousRequestCount) or (FIdleThreads>0) or
       not IsThrottledDelay(FThreadCreationAt,FThreadCount) then
      Exit;
    if FThreadCount<FMaxThreads then
      Grow:=1
    else if FUnlimitedWorkerThreadsWhenBlocked then
      begin
      Grow:=FMaxThreads div 2+1;
      if Grow>Requests then
        Grow:=Requests;
      end
    else
      Exit;
    {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.GrowIfStarved','Requests %d, threads %d of %d: adding %d',[Requests,FThreadCount,FMaxThreads,Grow]);{$ENDIF USE_THREADLOG}
    FPreviousRequestCount:=Requests;
    for I:=1 to Grow do
      AddThreadToPool;
  finally
    UnLockQueue;
  end;
end;

function TThreadPool.AddThreadToPool : TQueueWorkerThread;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.AddThreadToPool','Enter');{$ENDIF USE_THREADLOG}
  FThreadCreationAt:=GetTickCount64;
  Result:=TQueueWorkerThread.Create(Self);
  AtomicIncrement(FThreadCount);
  {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.AddThreadToPool','Leave (thread count: %d)',[FThreadCount]);{$ENDIF USE_THREADLOG}
end;

function TThreadPool.DoMonitor : TMonitorResult;

var
  I: Integer;
  AvgCPU: Cardinal;
  Woken: Boolean;

begin
  Result:=TMonitorResult.mrContinue;
  if FShutdown then
    Exit(TMonitorResult.mrTerminate);
  // A producer that found every allowed worker busy starts the round at once.
  Woken:=FMonitorEvent.WaitFor(MonitorThreadDelay)=wrSignaled;
  if Woken then
    FMonitorEvent.ResetEvent;
  FCPUUsage:=TThread.GetCPUUsage(FCPUInfo);
  FCPUUsageArray[FCurUsageSlot]:=FCPUUsage;
  if FCurUsageSlot = NumCPUUsageSamples - 1 then
    FCurUsageSlot:=0
  else
    Inc(FCurUsageSlot);
  AvgCPU:=0;
  for I:=0 to NumCPUUsageSamples - 1 do
    Inc(AvgCPU, FCPUUsageArray[I]);
  FAvgCPUUsage:=AvgCPU div TThreadPool.NumCPUUsageSamples;
  // Busy processors mean busy workers, not blocked ones.
  if FCPUUsage < MinCPUUsage then
    GrowIfStarved;
  if FShutdown then
    Exit(TMonitorResult.mrTerminate)
  else if not Woken and HaveNoWorkers then
    Exit(TMonitorResult.mrIdle);
end;


{ *********************************************************************
  TThreadPool.TControlFlag
  *********************************************************************}

function TThreadPool.TControlFlag.Increment: Integer;
begin
  Result:=AtomicIncrement(FFlag);
end;

function TThreadPool.TControlFlag.Value: Integer;
begin
  Result:=AtomicCmpExchange(FFlag,0,0);
end;

constructor TThreadPool.TControlFlag.Create;
begin
  inherited Create;
  FFlag:=-1;
end;

{ *********************************************************************
  TThreadPool.TAbstractWorkerData
  *********************************************************************}

function TThreadPool.TAbstractWorkerData.ShouldExecute: Boolean;
begin
  // This is a misnomer. if ShouldExecute is true, the task will NOT be executed.
  Result:=FControlFlag.Increment>0;
end;

class function TThreadPool.TAbstractWorkerData.NewInstance: TObject;

var
  Obj : Pointer;
  ObjCache: TObjectCache;

begin
  Result:=Nil;
  if TThreadPool.Caches.TryGetValue(Self,ObjCache) then
    begin
    Obj:=ObjCache.Remove;
    if Assigned(Obj) then
      begin
      Result:=InitInstance(Obj);
      TAbstractWorkerData(Result).FRefCount:=1;
      end;
    end;
  If Not Assigned(Result) then
    Result:=inherited NewInstance;
end;

procedure TThreadPool.TAbstractWorkerData.FreeInstance;
var
  ObjCache: TObjectCache;
begin
  CleanupInstance;
  if TThreadPool.Caches.TryGetValue(Self.ClassType,ObjCache) then
    if ObjCache.Insert(Pointer(Self)) then
      Exit;
  Inherited;
end;

constructor TThreadPool.TAbstractWorkerData.Create(aFlag: IControlFlag);
begin
  Inherited Create;
  FControlFlag:=aFlag;
end;

{ *********************************************************************
  TThreadPool.TWorkerData
  *********************************************************************}

procedure TThreadPool.TWorkerData.ExecuteWork;
begin
  if Assigned(FWorkerEvent) then
    FWorkerEvent(FSender)
  else if Assigned(FProc) then
    FProc;
end;

constructor TThreadPool.TWorkerData.Create(aFlag: IControlFlag; aSender: TObject; aEvent: TNotifyEvent);
begin
  Inherited Create(aFlag);
  FSender:=aSender;
  FWorkerEvent:=aEvent;
end;

constructor TThreadPool.TWorkerData.Create(aFlag: IControlFlag; aProc: TProcRef);
begin
  Inherited Create(aFlag);
  FProc:=aProc;
end;

{ *********************************************************************
  TThreadPool.TBaseWorkerThread
  *********************************************************************}


class function TThreadPool.TBaseWorkerThread.NextWorkerID: Integer;
begin
  Result:=AtomicIncrement(FWorkerID);
end;

procedure TThreadPool.TBaseWorkerThread.RemoveFromPool;
begin

  if Assigned(FThreadPool) then
    FThreadPool.RemoveThread(Self);
  // So we don't try to do it again.
  FThreadPool:=Nil;
end;

procedure TThreadPool.TBaseWorkerThread.SafeTerminate;
begin
  FreeOnTerminate:=True;
  RemoveFromPool;
  Terminate;
end;

procedure TThreadPool.TBaseWorkerThread.TerminatedSet;
begin
  { ThreadProc deliberately skips Execute when a suspended/new worker is
    terminated before its first time slice.  Such a worker will never signal
    FRunningEvent from Execute, so release BeforeDestruction here as well. }
  if Assigned(FRunningEvent) then
    FRunningEvent.SetEvent;
  inherited TerminatedSet;
end;

Function TThreadPool.TBaseWorkerThread.GetWorkerThreadName : string;

begin
  Result:=Format(SWorkerThreadName,[ClassName,FMyWorkerID,Pointer(ThreadPool)]);
end;

procedure TThreadPool.TBaseWorkerThread.Execute;

begin
  NameThreadForDebugging(GetWorkerThreadName);
  FRunningEvent.SetEvent;
end;

constructor TThreadPool.TBaseWorkerThread.Create(aThreadPool: TThreadPool);
begin
  { Do not start the OS thread before the fields used by Execute have been
    initialized.  Starting it from the inherited constructor allowed Execute
    to observe FRunningEvent=nil; the later destructor then waited forever on
    the newly-created, never-signalled event. }
  inherited Create(True);
  FRunningEvent:=TLightweightEvent.Create(False);
  FThreadPool:= AThreadPool;
  if Assigned(FThreadPool) then
    FThreadPool.NewThread(Self);
  FMyWorkerID:=NextWorkerID;
  FreeOnTerminate:=True;
  Start;
end;

destructor TThreadPool.TBaseWorkerThread.Destroy;
begin
  RemoveFromPool;
  FreeAndNil(FRunningEvent);
  inherited Destroy;
end;

procedure TThreadPool.TBaseWorkerThread.BeforeDestruction;
begin
  if FRunningEvent <> nil then
    FRunningEvent.WaitFor(INFINITE);
  inherited BeforeDestruction;
end;

{ *********************************************************************
  TThreadPool.TQueueWorkerThread
  *********************************************************************}

procedure TThreadPool.TQueueWorkerThread.ExecuteWorkItem(var aItem: IThreadPoolWorkItem);

begin
  try
    aItem.ExecuteWork;
  except
    On E : Exception do
      FWorkException:=E;
  end;
  aItem:=nil;
end;

procedure TThreadPool.TQueueWorkerThread.WrapExecute(var aItem : IThreadPoolWorkItem);

begin
  ThreadPool.SignalExecuting(Self);
  if aItem.ShouldExecute then
    begin
    aItem:=nil;
    Exit;
    end;
  ExecuteWorkItem(aItem);
end;

procedure TThreadPool.TQueueWorkerThread.AdjustWaitTime;
begin
  if FCheckWaitTime < MaxCheckWaitTime then
    FCheckWaitTime:=(FCheckWaitTime *2)
  else
    FCheckWaitTime:=IdleTimeout;
end;

procedure TThreadPool.TQueueWorkerThread.Execute;

var
  Itm: IThreadPoolWorkItem;

begin
  // Run the callback in the worker, outside the queue lock held by its creator.
  // A callback may queue work in this pool; Delphi also ignores its exception.
  try
    if Assigned(ThreadPool.FOnThreadStart) then
      ThreadPool.FOnThreadStart(Self);
  except
  end;
  inherited Execute;
  FCheckWaitTime:=IdleTimeout;
  ThreadPool.RegisterWorkerThread(Self);
  try
    While not Terminated do
      begin
      Itm:=Nil;
      // If we do not have work assigned
      If not WorkQueue.LocalPop(Itm) then
        // Ask for more work
        if not ThreadPool.GetWorkItemForThread(Self,Itm) then
          begin
          // if it returned false, we stop
          {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.TQueueWorkerThread.Execute','No work, stopping');{$ENDIF USE_THREADLOG}
          Terminate;
          end;
      if Assigned(Itm) then
        begin
        {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.TQueueWorkerThread.Execute','Calling WrapExecute. Idle: %s',[BToS(Idle)]);{$ENDIF USE_THREADLOG}
        WrapExecute(Itm);
        FCheckWaitTime:=IdleTimeout;
        {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.TQueueWorkerThread.Execute','Called WrapExecute. Idle: %s',[BToS(Idle)]);{$ENDIF USE_THREADLOG}
        end;
      if Terminated then
        {$IFDEF USE_THREADLOG}ThreadLog('TThreadPool.TQueueWorkerThread.Execute','Thread Terminated');{$ENDIF USE_THREADLOG}
      end;
  finally
    ThreadPool.UnRegisterWorkerThread(Self);
  end;
end;

constructor TThreadPool.TQueueWorkerThread.Create(aThreadPool: TThreadPool);
begin
  FWorkQueue:=TWorkStealingQueueThreadPoolWorkItem.Create;
  Inherited Create(aThreadPool);
end;

destructor TThreadPool.TQueueWorkerThread.Destroy;
begin
  FreeAndNil(FWorkQueue);
  inherited Destroy;
end;

{ *********************************************************************
  TThreadPool.TThreadPoolMonitor
  *********************************************************************}



function TThreadPool.TThreadPoolMonitor.GetThreadName : string;

begin
  Result:=Format('Thread Pool Monitor Thread - %s ThreadPool - %p', [ClassName, Pointer(FThreadPool)])
end;

procedure TThreadPool.TThreadPoolMonitor.Execute;

Var
  IdleCount : Integer;
  Res : TMonitorResult;

begin
  try
  NameThreadForDebugging(GetThreadName);
  // A wake ends the first delay and stays set: the first round goes at once.
  FThreadPool.FMonitorEvent.WaitFor(TThreadPool.MonitorThreadDelay);
  FThreadPool.InitCPUStats;
  IdleCount:=TThreadPool.MonitorIdleLimit;
  while not Terminated do
    begin
    Res:=FThreadPool.DoMonitor;
    case res of
      TMonitorResult.mrContinue :
        IdleCount:=TThreadPool.MonitorIdleLimit;
      TMonitorResult.mrIdle :
        begin
        Dec(IdleCount);
        if IdleCount=0 then
          Terminate;
        end;
      TMonitorResult.mrTerminate:
        Terminate;
    end;
    end;
    FThreadPool.StopCPUStats;

  finally
    FThreadPool.FMonitorStatus:=MonitorNone;
  end;
end;

constructor TThreadPool.TThreadPoolMonitor.Create(aThreadPool: TThreadPool);
begin
  FThreadPool:=aThreadPool;
  FreeOnTerminate:=True;
  Inherited Create(False);
end;

{ *********************************************************************
  TThreadPoolStats
  *********************************************************************}

class function TThreadPoolStats.GetCurrent: TThreadPoolStats;
begin
  Result.Assign(TThreadPool.Current);
end;

class function TThreadPoolStats.GetDefault: TThreadPoolStats;
begin
  Result.Assign(TThreadPool.Default);
end;

class function TThreadPoolStats.Get(const aPool: TThreadPool): TThreadPoolStats;
begin
  Result.Assign(aPool);
end;

Procedure TThreadPoolStats.Assign(const aPool: TThreadPool);

begin
  FWorkerThreadCount:=aPool.FThreadCount;
  FMinLimitWorkerThreadCount:=aPool.FMinThreads;
  FMaxLimitWorkerThreadCount:=aPool.FMaxThreads;
  FIdleWorkerThreadCount:=aPool.FIdleThreads;
  FQueuedRequestCount:=aPool.FRequestCount;
  // Workers leave on their idle timeout; none retires or suspends itself.
  FRetiredWorkerThreadCount:=0;
  FAverageCPUUsage:=aPool.FAvgCPUUsage;
  FCurrentCPUUsage:=aPool.FCPUUsage;
  FThreadSuspended:=0;
  FLastSuspendTick:=0;
  FLastThreadCreationTick:=aPool.FThreadCreationAt;
  FLastQueuedRequestCount:=aPool.FPreviousRequestCount;
end;

{ *********************************************************************
  TTask
  *********************************************************************}

class function TTask.NewId: Integer;
begin
  Result:=AtomicIncrement(FNextTaskID);
end;

class function TTask.CurrentTask: ITask;
begin
  Result:=_CurrentTask;
end;

constructor TTask.Create;
begin
  raise ENoConstructException.Create(SErrInvalidTaskConstructor);
end;

destructor TTask.Destroy;
begin
  FreeAndNil(FException);
  FreeAndNil(FDoneEvent);
  inherited Destroy;
end;

class function TTask.Run(aSender: TObject; aEvent: TNotifyEvent; aPool: TThreadPool): ITask;
begin
  Result:=TTask.Create(aSender,aEvent,aPool);
  Result.Start;
end;

class function TTask.Run(aSender: TObject; aEvent: TNotifyEvent): ITask; overload; static; inline;
begin
  Result:=Run(aSender,aEvent,TThreadPool.Default);
end;

class function TTask.Run(const aFunc: TProcRef; aPool: TThreadPool): ITask;
begin
  Result:=TTask.Create(aFunc,aPool);
  Result.Start;
end;

class function TTask.Run(const aFunc: TProcRef): ITask;
begin
  Result:=Run(aFunc,TThreadPool.Default);
end;

function TTask.GetIsComplete: Boolean;
begin
  Result:=(FStateFlags*CompleteStates) <> [];
end;

function TTask.GetIsReplicating: Boolean;
begin
  Result:=(FStateFlags*ReplicatingStates) = [TOptionStateFlag.Replicating];
end;

function TTask.GetHasExceptions: Boolean;
begin
  Result:=(FException<>nil) or (Length(FTasksWithExceptions)>0);
end;

function TTask.GetIsCanceled: Boolean;
begin
  Result:=(FStateFlags*CanceledStates)=[TOptionStateFlag.Canceled];
end;

function TTask.GetIsQueued: Boolean;
begin
  Result:=(FStateFlags*[TOptionStateFlag.Started,TOptionStateFlag.CallbackRun,
    TOptionStateFlag.Canceled,TOptionStateFlag.Faulted,TOptionStateFlag.Complete])=
    [TOptionStateFlag.Started];
end;

function TTask.GetDoneEvent: TLightweightEvent;
begin
  Result:=FDoneEvent;
end;

function TTask.UpdateStateAtomic(aNewState: TOptionStateFlags; aInvalidStates: TOptionStateFlags): Boolean;
var
  Old : TOptionStateFlags;

begin
  Result:=UpdateStateAtomic(aNewState,aInvalidStates,Old);
end;

Procedure TTask.LockState;

begin
  FStateLock.Enter;
end;

Procedure TTask.UnLockState;

begin
  FStateLock.Exit;
end;

Procedure TTask.CalcStatus;

  function GetNewStatus : TTaskStatus;

  var
    OSF : TOptionStateFlags;

    Function Have(F : TOptionStateFlag) : boolean; inline;
    begin
      Result:=F in OSF;
    end;

  begin
    OSF:=FStateFlags;
    if Have(TOptionStateFlag.Faulted) then
      Exit(TTaskStatus.Exception);
    if Have(TOptionStateFlag.Canceled) then
      Exit(TTaskStatus.Canceled);
    if Have(TOptionStateFlag.Complete) then
      Exit(TTaskStatus.Completed);
    if Have(TOptionStateFlag.ChildWait) then
      Exit(TTaskStatus.WaitingForChildren);
    if Have(TOptionStateFlag.CallbackRun) then
      Exit(TTaskStatus.Running);
    if Have(TOptionStateFlag.Started) then
      Exit(TTaskStatus.WaitingToRun);
    Result:=TTaskStatus.Created;
  end;

begin
  FStatus:=GetNewStatus;
end;

procedure TTask.ForceStateFlags(aFlags : TOptionStateFlags);

begin
  FStateFlags:=aFlags;
  CalcStatus;
end;

function TTask.UpdateStateAtomic(aNewState: TOptionStateFlags; aInvalidStates: TOptionStateFlags; out aOldState: TOptionStateFlags
  ): Boolean;

begin
  LockState;
  try
    aOldState:=FStateFlags;
    Result:=(FStateFlags*aInvalidStates)=[];
    if Not Result then
      Exit;
    ForceStateFlags(FStateFlags+aNewState);
  finally
    UnLockState;
  end;
end;

procedure TTask.SetTaskStop;
begin
  // 0 -> 1, and >1 means not execute
  FControlFlag.Increment;
end;

function TTask.ShouldCreateReplica: Boolean;
begin
  // Indicate we CAN create a replica (will be overridden in TParallelTask)
  // The actual replication will be decided on the basis of flags.
  Result:=False;
end;

function TTask.CreateReplicaTask(const aParams : TTaskParams) : TTask;

begin
  Result:=TTask.Create(aParams);
end;

function TTask.CreateReplicaTask(const aProc: TProcRef; aParent: TTask; aCreateFlags: TCreateFlags;
  const aParentControlFlag: TThreadPool.IControlFlag): TTask;

var
  aParams : TTaskParams;

begin
  aParams:=Default(TTaskParams);
  aParams.Proc:=aProc;
  aParams.Parent:=aParent;
  aParams.Pool:=ThreadPool;
  aParams.CreateFlags:=aCreateFlags;
  aParams.ParentControlFlag:=aParentControlFlag;
  Result:=CreateReplicaTask(aParams);
  Result.FReplicaRoot:=aParent;
end;

procedure TTask.CheckFaulted;

var
  E: TObject;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TTask.CheckFaulted','CheckFaulted');{$ENDIF USE_THREADLOG}
  E:=GetExceptionObject;
  if Assigned(E) then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.CheckFaulted','CheckFaulted have error');{$ENDIF USE_THREADLOG}
    SetRaisedState;
    raise E;
    end;
end;


procedure TTask.SetComplete;

begin
  FDoneEvent.SetEvent;
end;

procedure TTask.AddChild;
begin
  AtomicIncrement(FSubTasks);
end;

procedure TTask.ForgetChild;
begin
  AtomicDecrement(FSubTasks);
end;

function TTask.InternalExecuteNow: Boolean;
begin
  if IsQueued then
    Result:=TryExecuteNow(True)
  else
    Result:=False;
end;

function TTask.GetExceptionObject: Exception;

var
  T : TTask;
  Exceptions : TExceptionList;

begin
  Result:=Nil;
  if not HasExceptions then
    Exit;
  if Length(FTasksWithExceptions)=0 then
    begin
    // Object is not nil since HasExceptions returned true.
    LockState;
    try
      if FException is EAggregateException then
        Result:=Exception(FException)
      else
        Result:=EAggregateException.Create([Exception(FException)]);
      FException:=Nil;
      Exit;
    finally
      UnlockState;
    end;
    end;
  Exceptions:=TExceptionList.Create(Length(FTasksWithExceptions)+1);
  if assigned(FException) then
    begin
    LockState;
    try
      Exceptions.Add(FException as Exception);
      FException:=Nil;
    Finally
      UnlockState;
    end;
    end;
  for T in FTasksWithExceptions do
    begin
    T.LockState;
    try
      Exceptions.AddFromTask(T);
      FreeAndNil(T.FException);
    finally
      T.UnlockState;
    end;
    end;
  Result:=EAggregateException.Create(Exceptions.Truncate);
end;



function TTask.GetWasExceptionRaised: Boolean;
begin
  Result:=TOptionStateFlag.Raised in FStateFlags;
end;

procedure TTask.QueueEvents;
begin
  FParams.Pool.DoQueueWorkItem(Self,FParams.Pool.QueueThread);
end;

procedure TTask.Complete(UserEventRan: Boolean);

var
  I,Last: Integer;
  LastTask : Boolean;
begin
  if not UserEventRan then
    begin
    IntermediateCompletion;
    exit;
    end;
  LastTask:=((FSubTasks=1) and not IsReplicating) or (AtomicDecrement(FSubTasks)<=0);
  if LastTask then
    IntermediateCompletion
  else
    UpdateStateAtomic([TOptionStateFlag.ChildWait], [TOptionStateFlag.Faulted, TOptionStateFlag.Canceled, TOptionStateFlag.Complete]);
  if Length(FTasksWithExceptions)=0 then
    Exit;
  LockState;
  try
    Last:=Length(FTasksWithExceptions)-1;
    for I:=Last downto 0 do
      if TTask(FTasksWithExceptions[I]).WasExceptionRaised then
        begin
        if I<>Last then
          FTasksWithExceptions[I]:=FTasksWithExceptions[Last];
        FTasksWithExceptions[Last]:=Nil;
        Dec(Last);
        end;
    SetLength(FTasksWithExceptions,Last+1);
  finally
    UnLockState;
  end;
end;

procedure TTask.IntermediateCompletion;

var
  State: TOptionStateFlags;

begin
  State:=[];
  if HasExceptions then
    Include(State,TOptionStateFlag.Faulted);
  if IsCanceled then
    Include(State,TOptionStateFlag.Canceled);
  Include(State,TOptionStateFlag.Complete);
  if not UpdateStateAtomic(State,[TOptionStateFlag.Complete]) then
    Exit;
  SetComplete;
  FinalCompletion;
end;

procedure TTask.FinalCompletion;
begin
  if (FParams.Parent<>nil) and (TOptionStateFlag.Replica in FStateFlags) then
    FParams.Parent.HandleChildCompletion(Self);
  ProcessCompleteEvents;
end;

procedure TTask.ProcessCompleteEvents;

  function MakeProc(const ATask: ITask; const AProc: THREADING_SPECIALIZE TProc<ITask>): TProcRef;
  begin
    Result :=
      procedure
      begin
        AProc(ATask);
      end;
  end;


var
  ProcList : TITaskProcArray;
  I, Count : Integer;
  Proc : TITaskProc;

begin
  if FCompletedEventCount=0 then
    exit;
  Repeat
    LockState;
    try
      ProcList:=FCompletedEvents;
      Count:=FCompletedEventCount;
      FCompletedEvents:=Nil;
      FCompletedEventCount:=0;
    finally
      UnLockState;
    end;
    For I:=0 to Count-1 do
      begin
      Proc:=ProcList[i];
      if (TOptionStateFlag.ChildWait in FStateFlags) then
        // Schedule for later execution
        Run(MakeProc(Self,Proc),FParams.Pool)
      else
        try
          // Execute immediatly
          Proc(Self);
        except
          // What to do with an exception ??
        end;
      end;
  until (FCompletedEventCount=0);
end;

procedure TTask.SetRaisedState;
begin
  if Assigned(FParams.Parent) and (_CurrentTask=(FParams.Parent as ITask)) then
    UpdateStateAtomic([TOptionStateFlag.Raised], []);
end;

function TTask.InternalWork: Boolean;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TTask.InternalWork','Enter');{$ENDIF USE_THREADLOG}
  if not (TOptionStateFlag.CallbackRun in FStateFlags) and
    not UpdateStateAtomic([TOptionStateFlag.CallbackRun],
      [TOptionStateFlag.CallbackRun,TOptionStateFlag.Canceled,
       TOptionStateFlag.Faulted,TOptionStateFlag.Complete]) and
    not (TOptionStateFlag.Canceled in FStateFlags) then
      Exit(False);
  if IsCanceled then
    Complete(False)
  else
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.InternalWork','calling internalexecute');{$ENDIF USE_THREADLOG}
    InternalExecute(_CurrentTask);
    end;
  Result:=True;
end;

procedure TTask.InternalExecute(var aCurrentTaskVar: TTask);

var
  Old : TTask;
  Executed : Boolean;

begin
  Old:=aCurrentTaskVar;
  try
    aCurrentTaskVar:=Self;
    Execute;
    Executed:=not (HasExceptions or IsCanceled);
    Complete(Executed);
  finally
    aCurrentTaskVar:=Old;
  end;
end;

procedure TTask.CallUserCode;
begin
  if Assigned(FParams.Event) then
    FParams.Event(FParams.Sender)
  else if Assigned(FParams.Proc) then
    FParams.Proc;
end;

procedure TTask.ReplicaCallUserCode;
begin
  try
    FReplicaRoot.CallUserCode;
  except
    FReplicaRoot.HandleException(CurrentTask, TObject(AcquireExceptionObject));
    Complete(False);
  end;
end;

procedure TTask.Execute;
begin
  if IsReplicating then
    ExecuteReplicates(Self)
  else if Assigned(FReplicaRoot) then
    ReplicaCallUserCode
  else
    try
      CallUserCode;
    except
      HandleException(Self,TObject(AcquireExceptionObject));
    end;
end;

procedure TTask.ExecuteReplicates(const aRoot: TTask);

var
  Sub : ITask;

begin
  FReplicaRoot:=aRoot;
  While aRoot.ShouldCreateReplica do
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.ExecuteReplicates','Creating replica');{$ENDIF USE_THREADLOG}
    Sub:=aRoot.CreateReplicaTask(nil,aRoot,[TCreateFlag.Replicating, TCreateFlag.Replica],FParams.ParentControlFlag);
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.ExecuteReplicates','Starting replica');{$ENDIF USE_THREADLOG}
    Sub.Start;
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.ExecuteReplicates','Started replica');{$ENDIF USE_THREADLOG}
    end;
  ReplicaCallUserCode;
end;


procedure TTask.HandleException(const aChildTask: ITask; const aException: TObject);

begin
  HandleException(aChildTask as TTask,aException)
end;

procedure TTask.HandleException(const aChildTask: TTask; const aException: TObject);


var
  I,Len : Integer;

begin
  if aChildTask=Self then
    begin
    SetExceptionObject(aException);
    Exit;
    end;
  LockState;
  try
    aChildTask.SetExceptionObject(aException);
    Len:=Length(FTasksWithExceptions);
    I:=Len-1;
    While (I>=0) and (FTasksWithExceptions[i].FTaskId<>aChildTask.FTaskId) do
      Dec(I);
    if I<0 then
      begin
      SetLength(FTasksWithExceptions,Len+1);
      FTasksWithExceptions[Len]:=aChildTask;
      end;
  finally
    UnlockState;
  end;
end;

function TTask.MarkAsStarted: Boolean;
begin
  Result:=UpdateStateAtomic([TOptionStateFlag.Started],[TOptionStateFlag.Started,TOptionStateFlag.Canceled]);
end;

function TTask.TryExecuteNow(aWasQueued: Boolean): Boolean;

begin
  Result:=not aWasQueued or FParams.Pool.DoRemoveWorkItem(Self);
  if not Result then
    Exit;
  AtomicDecrement(FParams.Pool.FRequestCount);
  Result:=InternalWork;
end;

procedure TTask.ExecuteWork;
begin
  try
    InternalWork;
  except
    HandleException(Self, TObject(AcquireExceptionObject));
    Complete(False);
  end;
end;

function TTask.ShouldExecute: Boolean;
begin
  Result:=inherited ShouldExecute;
  if not Result then
    { The state lock arbitrates the dequeue/cancel race.  Once CallbackRun is
      published cancellation must wait for the callback path; if cancellation
      won first, this worker skips user code. }
    Result:=not UpdateStateAtomic([TOptionStateFlag.CallbackRun],
      [TOptionStateFlag.Canceled,TOptionStateFlag.Faulted,TOptionStateFlag.Complete]);
  if Result then
    Complete(False);
end;

function TTask.Wait(aTimeout: Cardinal): Boolean;

  Procedure RunChecks; inline;
  begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.Wait.RunChecks','Enter');{$ENDIF USE_THREADLOG}
    try
      CheckCanceled;
      CheckFaulted;
    finally
      {$IFDEF USE_THREADLOG}ThreadLog('TTask.Wait.RunChecks','Leave');{$ENDIF USE_THREADLOG}
    end;
  end;

var
  NeedSync : Boolean;
  Watch : TStopWatch;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TTask.Wait','Enter (atimeout: %d) ',[aTimeout]);{$ENDIF USE_THREADLOG}
  Result:=IsComplete;
  if Result then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.Wait','Complete');{$ENDIF USE_THREADLOG}
    Runchecks;
    Exit;
    end;
  NeedSync:=(TThread.CurrentThread.ThreadID=MainThreadID) and FParams.Pool.Interactive;
  if Not NeedSync then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TTask.Wait','Waiting for done event (%d)',[aTimeout]);{$ENDIF USE_THREADLOG}
    Result:=DoneEvent.WaitFor(aTimeout)<>wrTimeout;
    if Result then
      RunChecks;
    end
  else
    begin
    if aTimeOut<>INFINITE then
      Watch:=TStopWatch.StartNew;
    Repeat
      CheckSynchronize(1);
    until IsComplete or
      ((aTimeOut<>INFINITE) and (Watch.ElapsedMilliseconds>=aTimeOut));
    Result:=IsComplete;
    if Result then
      RunChecks;
    end;
end;

function TTask.Wait(const aTimeout: TTimeSpan): Boolean;
begin
  Result:=Wait(TimespanToMilliseconds(aTimeOut));
end;

procedure TTask.DoCancel(aDestroying : Boolean);

var
  LFlags, OldFlags: TOptionStateFlags;

begin
  if IsComplete then
    exit;
  SetTaskStop;
  LFlags:=[TOptionStateFlag.Canceled];
  if aDestroying then
    Include(LFlags, TOptionStateFlag.Destroying);
  if not UpdateStateAtomic(LFlags,[TOptionStateFlag.Faulted,TOptionStateFlag.Complete],OldFlags) then
    Exit;
  { A task not yet claimed by a worker is terminal immediately.  A claimed
    callback owns completion and publishes it only after leaving user code. }
  if not (TOptionStateFlag.CallbackRun in OldFlags) then
    Complete(False);
end;

procedure TTask.Cancel;

begin
  DoCancel(False);
end;


procedure TTask.CheckCanceled;
begin
  if TOptionStateFlag.Canceled in FStateFlags then
    raise EOperationCancelled.Create(SOperationCancelled);
end;

function TTask.Start: ITask;
begin
  if IsComplete then
    raise EInvalidOperation.Create(SCannotStartCompletedTask);
  Result:=Self;
  if Not MarkAsStarted then
    Exit;
  try
    GetDoneEvent;
    QueueEvents;
  except
    Complete(False);
    raise;
  end;
end;

function TTask.GetId: Integer;
begin
  Result:=FTaskID;
end;

function TTask.GetStatus: TTaskStatus;

begin
  Result:=FStatus;
end;

procedure TTask.AddCompleteEvent(const aProc: TITaskProc);
var
  CallNow: Boolean;
begin
  CallNow:=False;
  LockState;
  try
    CallNow:=IsComplete;
    if not CallNow then
      begin
      If Length(FCompletedEvents)=FCompletedEventCount then
        SetLength(FCompletedEvents,FCompletedEventCount+32);
      FCompletedEvents[FCompletedEventCount]:=aProc;
      Inc(FCompletedEventCount);
      end;
  finally
    UnlockState;
  end;
  if CallNow then
    aProc(Self);
end;

procedure TTask.HandleChildCompletion(const aTask: TAbstractTask.IInternalTask);

begin
  HandleChildCompletion(aTask as TTask);
end;

procedure TTask.HandleChildCompletion(const aTask: TTask);


begin
  if Not Assigned(aTask) then
    exit;
  if aTask.HasExceptions and not aTask.WasExceptionRaised then
    HandleException(aTask,aTask.GetExceptionObject);
  if AtomicDecrement(FSubTasks)=0 then
    IntermediateCompletion;
end;

procedure TTask.SetExceptionObject(const aException: TObject);

begin
  if not assigned(FException) then
    FException:=aException
  else if aException is Exception then
    begin
    if not (FException is EAggregateException) then
      // This is not correct, we don't know whether FException is an Exception.
      FException:=EAggregateException.Create([Exception(FException),Exception(aException)])
    else
      EAggregateException(FException).Add(Exception(aException))
    end;
end;

procedure TTask.RemoveCompleteEvent(const aProc: TITaskProc);

var
  I,Idx : Integer;

begin
  If FCompletedEventCount=0 then
    exit;// Don't bother locking
  LockState;
  try
    Idx:=FCompletedEventCount-1;
    While (Idx>=0) and (FCompletedEvents[Idx]<>aProc) do
      Dec(Idx);
    if Idx>=0 then
      begin
      For I:=Idx to FCompletedEventCount-2 do
        FCompletedEvents[I]:=FCompletedEvents[I+1];
      Dec(FCompletedEventCount);
      FCompletedEvents[FCompletedEventCount]:=Nil;
      end;
  finally
    UnLockState;
  end;
end;

function TTask.GetControlFlag: TThreadPool.IControlFlag;
begin
  Result:=FControlFlag;
end;

constructor TTask.Create(const aParams : TTaskParams);

begin
  inherited Create(TThreadPool.NewControlFlag);
  FTaskID:=NewId;
  FSubTasks:=1;
  FParams:=aParams;
  FParams.ResolvePool;
  if FParams.Parent<>nil then
    FParams.Parent.AddChild;
  FStateFlags:=[];
  FStatus:=TTaskStatus.Created;
  if TCreateFlag.Replicating in aParams.CreateFlags then
    Include(FStateFlags, TOptionStateFlag.Replicating);
  if TCreateFlag.Replica in aParams.CreateFlags then
    Include(FStateFlags, TOptionStateFlag.Replica);
  FStateLock:=TSpinLock.Create(False);
  FDoneEvent:=TEvent.Create;
end;

class function TTask.DoWaitForAll(const aTasks: array of ITask; aTimeout: Cardinal): Boolean;
var
  I: Integer;
  Task: TTask;
  TaskI : ITask;
  ExceptionCount,CancelCount : Integer;
  ExceptionList: TExceptionList;
  Watch : TStopWatch;
  Remaining: Cardinal;
  NeedSync: Boolean;

begin
  Result:=True;
  ExceptionCount:=0;
  CancelCount:=0;
  NeedSync:=False;
  if aTimeout<>INFINITE then
    Watch:=TStopWatch.StartNew;
  for TaskI in aTasks do
    begin
    Task:=TaskI as TTask;
    if Task=Nil then
      raise EArgumentNilException.Create(SErrWaitNilTask);
    if not Task.IsComplete and Task.FParams.Pool.FInteractive then
      NeedSync:=True;
    end;
  NeedSync:=NeedSync and
    (TThread.CurrentThread.ThreadID=MainThreadID);
  for TaskI in aTasks do
    begin
    Task:=TaskI as TTask;
    if not Task.IsComplete then
      begin
      if (aTimeout=INFINITE) and Task.InternalExecuteNow and Task.IsComplete then
        Continue;
      if NeedSync then
        begin
        Repeat
          CheckSynchronize(1);
          if Task.DoneEvent.WaitFor(0)=wrSignaled then
            Break;
        until (aTimeout<>INFINITE) and (Watch.ElapsedMilliseconds>=aTimeout);
        Result:=Task.IsComplete;
        end
      else
        begin
        if aTimeout=INFINITE then
          Remaining:=INFINITE
        else if Watch.ElapsedMilliseconds>=aTimeout then
          Remaining:=0
        else
          Remaining:=aTimeout-Cardinal(Watch.ElapsedMilliseconds);
        Result:=Task.DoneEvent.WaitFor(Remaining)=wrSignaled;
        end;
      if not Result then
        Break;
      end;
    end;
  if not Result then
    Exit;
  for TaskI in aTasks do
    begin
    Task:=TaskI as TTask;
    if Task.HasExceptions then
      Inc(ExceptionCount)
    else if Task.IsCanceled then
      Inc(CancelCount);
    end;
  if (ExceptionCount=0) and (CancelCount=0) then
    Exit;
  if (ExceptionCount=0) and (CancelCount>0) then
    raise EOperationCancelled.Create(SErrOneOrMoreTasksCancelled);
  ExceptionList:=TExceptionList.create(Length(aTasks));
  for TaskI in aTasks do
    ExceptionList.AddFromTask(TaskI as TTask);
  if ExceptionList.Count>0 then
    raise EAggregateException.Create(ExceptionList.Truncate);
end;

class function TTask.DoWaitForAny(const aTasks: array of ITask; aTimeout: Cardinal): Integer;
var
  CompleteTask: ITask;
  Task: TTask;
  Lock : TSpinLock;
  Event : TEvent;
  CompleteProc: TITaskProc;
  I: Integer;
  NeedSync : Boolean;
  Waiting: Boolean;
  Watch : TStopWatch;
  WaitResult: TWaitResult;

begin
  Result:=-1;
  NeedSync:=False;
  for I:=Low(aTasks) to High(aTasks) do
    begin
    Task:=aTasks[I] as TTask;
    if Task=Nil then
      raise EArgumentNilException.Create(SErrWaitNilTask);
    if (Result=-1) and Task.IsComplete then
      Result:=I;
    if not Task.IsComplete and Task.FParams.Pool.FInteractive then
      NeedSync:=True;
    end;
  if Result<>-1 then
    begin
    aTasks[Result].Wait(0);
    exit;
    end;
  if Length(aTasks)=0 then
    Exit;
  NeedSync:=NeedSync and
    (TThread.CurrentThread.ThreadID=MainThreadID);
  Lock:=TSpinLock.Create(False);
  Waiting:=True;
  CompleteTask:=Nil;
  Event:=TEvent.Create;
  CompleteProc:=procedure (aTask: ITask)
    begin
    Lock.Enter;
    try
      if Waiting and (CompleteTask=Nil) then
        begin
        CompleteTask:=aTask;
        Event.SetEvent;
        end;
    finally
      Lock.Exit;
    end;
    end;
  try
    try
      for I:=Low(aTasks) to High(aTasks) do
        (aTasks[I] as TTask).AddCompleteEvent(CompleteProc);
      if NeedSync then
        begin
        if aTimeout<>INFINITE then
          Watch:=TStopWatch.StartNew;
        Repeat
          WaitResult:=Event.WaitFor(0);
          if WaitResult=wrSignaled then
            Break;
          CheckSynchronize(1);
        until (aTimeout<>INFINITE) and (Watch.ElapsedMilliseconds>=aTimeout);
        if WaitResult<>wrSignaled then
          WaitResult:=Event.WaitFor(0);
        end
      else
        WaitResult:=Event.WaitFor(aTimeout);
    finally
      Lock.Enter;
      try
        Waiting:=False;
      finally
        Lock.Exit;
      end;
      for I:=Low(aTasks) to High(aTasks) do
        (aTasks[I] as TTask).RemoveCompleteEvent(CompleteProc);
    end;
    if WaitResult=wrSignaled then
      for I:=Low(aTasks) to High(aTasks) do
        if (CompleteTask<>Nil) and
          ((aTasks[I] as TTask)=(CompleteTask as TTask)) then
          begin
          Result:=I;
          Break;
          end;
    if Result<>-1 then
      aTasks[Result].Wait(0);
  finally
    CompleteProc:=Nil;
    FreeAndNil(Event);
  end;
end;

class function TTask.TimespanToMilliseconds(const aTimeout: TTimeSpan): Cardinal;
var
  Total: Int64;
begin
  Total:=Trunc(aTimeout.TotalMilliseconds);
  if (Total<0) or (Total>$7fffffff) then
    raise EArgumentOutOfRangeException.Create(SErrInvalidTimeout);
  Result:=Cardinal(Total);
end;



class function TTask.Create(aSender: TObject; aEvent: TNotifyEvent; const aPool: TThreadPool): ITask;
var
  Params : TTaskParams;
begin
  Params:=Default(TTaskParams);
  Params.Sender:=aSender;
  Params.Event:=aEvent;
  Params.Pool:=aPool;
  Result:=TTask.Create(Params);
end;

class function TTask.Create(const aProc: TProcRef; aPool: TThreadPool): ITask;
var
  Params : TTaskParams;
begin
  Params:=Default(TTaskParams);
  Params.Proc:=aProc;
  Params.Pool:=aPool;
  Result:=TTask.Create(Params);
end;

class function TTask.Create(aSender: TObject; aEvent: TNotifyEvent): ITask;
begin
  Result:=Create(aSender,aEvent,TThreadPool.Default);
end;

class function TTask.Create(const aProc: TProcRef): ITask;
begin
  Result:=Create(aProc,TThreadPool.Default);
end;

class function TTask.WaitForAll(const aTasks: array of ITask): Boolean;
begin
  Result:=WaitForAll(aTasks,INFINITE);
end;

class function TTask.WaitForAll(const aTasks: array of ITask; aTimeout: Cardinal): Boolean;
begin
  Result:=DoWaitForAll(aTasks,aTimeOut);
end;

class function TTask.WaitForAll(const aTasks: array of ITask; const aTimeout: TTimeSpan): Boolean;
begin
  Result:=WaitForAll(aTasks,TimespanToMilliseconds(aTimeOut));
end;

class function TTask.WaitForAny(const aTasks: array of ITask): Integer;
begin
  Result:=WaitForAny(aTasks,INFINITE);
end;

class function TTask.WaitForAny(const aTasks: array of ITask; aTimeout: Cardinal): Integer;
begin
  Result:=DoWaitForAny(aTasks,aTimeOut);
end;

class function TTask.WaitForAny(const aTasks: array of ITask; const aTimeout: TTimeSpan): Integer;
begin
  Result:=WaitForAny(aTasks,TimespanToMilliseconds(aTimeOut));
end;

THREADING_GENERIC class function TTask.Future<T>(aSender: TObject; aEvent: THREADING_SPECIALIZE TFunctionEvent<T>) : THREADING_SPECIALIZE IFuture<T>;
begin
  Result:=THREADING_SPECIALIZE TFuture<T>.Create(aSender,aEvent,Nil,TThreadPool.Default);
  Result.StartFuture;
end;

THREADING_GENERIC class function TTask.Future<T>(aSender: TObject; aEvent: THREADING_SPECIALIZE TFunctionEvent<T>; aPool: TThreadPool): THREADING_SPECIALIZE IFuture<T>;
begin
  Result:=THREADING_SPECIALIZE TFuture<T>.Create(aSender,aEvent,Nil,aPool);
  Result.StartFuture;
end;

THREADING_GENERIC class function TTask.Future<T>(const aFunc: THREADING_SPECIALIZE TFunc<T>): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;

begin
  Result:=THREADING_SPECIALIZE TFuture<T>.Create(Nil,Nil,aFunc,TThreadPool.Default);
  Result.StartFuture;
end;

THREADING_GENERIC class function TTask.Future<T>(const aFunc: THREADING_SPECIALIZE TFunc<T>; aPool: TThreadPool): THREADING_SPECIALIZE IFuture<T>; overload; static; inline;

begin
  Result:=THREADING_SPECIALIZE TFuture<T>.Create(Nil,Nil,aFunc,aPool);
  Result.StartFuture;
end;

{ *********************************************************************
  TTask.TTaskParams
  *********************************************************************}

procedure TTask.TTaskParams.ResolvePool;
begin
  if Not Assigned(Pool) and Assigned(Parent) then
    Pool:=Parent.ThreadPool;
  if Not Assigned(Pool) then
    Pool:=TThreadPool.Current;
end;

{ *********************************************************************
  TFuture
  *********************************************************************}

procedure TFuture THREADING_PARAMS.RunFunc(Sender: TObject);
begin
  FResult:=Default(T);
  if Assigned(FFuncRef) then
    FResult:=FFuncRef()
  else if Assigned(FFuncEvent) then
    FResult:=FFuncEvent(Sender);
end;

function TFuture THREADING_PARAMS.StartFuture: THREADING_SPECIALIZE IFuture<T>;
begin
  inherited Start;
  Result:=Self;
end;

THREADING_GENERIC function TFuture THREADING_PARAMS.GetValue: T;
begin
  Wait;
  Result:=FResult;
end;

constructor TFuture THREADING_PARAMS.Create(aSender: TObject; aEvent: TFunctionEventT; const aFunc: THREADING_SPECIALIZE TFunc<T>; aPool: TThreadPool);

var
  Params : TTaskParams;

begin
  Params:=Default(TTaskParams);
  Params.Event:=@RunFunc;
  Params.Sender:=aSender;
  Params.Pool:=aPool;
  FFuncEvent:=aEvent;
  FFuncRef:=aFunc;
  inherited Create(Params);
end;


{ *********************************************************************
  TReplicableTask
  *********************************************************************}

constructor TEventJoinTask.Create(Sender: TObject; const AEvents: array of TNotifyEvent; APool: TThreadPool);
var
  I,Len : integer;
  Params : TTaskParams;

begin
  // Copy procs
  Len:=Length(AEvents);
  SetLength(FEventList,Len);
  For I:=0 to Len-1 do
    FEventList[I]:=aEvents[i];
  Params.Proc:=@JoinTasks;
  Params.Parent:=Self;
  Params.Pool:=aPool;
  Params.Sender:=Sender;
  Inherited Create(Params);
end;

procedure TEventJoinTask.JoinTasks;

var
  Proc : TParallel.TInt32Proc;
  Loop : TParallel.TInt32LoopProc;

begin
  Proc:=Procedure(aIndex : Integer)
    begin
      FEventList[aIndex](Self.FParams.Sender);
    end;
  Loop:=TParallel.TInt32LoopProc.create(0,Length(FEventList)-1,Proc);
  TParallel.Parallelize32(Loop,Self.ThreadPool);
end;

{ *********************************************************************
  TReplicableTask
  *********************************************************************}

function TReplicableTask.ShouldCreateReplica: Boolean;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.ShouldCreateReplica','Enter (TaskCount: %d)',[FTaskCount]);{$ENDIF USE_THREADLOG}
  Result:=False;
  if (FTaskCount<=0) then
    exit;
  AtomicDecrement(FTaskCount);
  Result:=FTaskCount>0;
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.ShouldCreateReplica','Leave: %s ',[BToS(Result)]);{$ENDIF USE_THREADLOG}
end;

function TReplicableTask.CreateReplicaTask(const aParams : TTaskParams): TTask;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.CreateReplicaTask','Enter');{$ENDIF USE_THREADLOG}
  Result:=TReplicatedTask.Create(aParams);
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.CreateReplicaTask','Leave');{$ENDIF USE_THREADLOG}
end;

constructor TReplicableTask.Create(const aParams : TTaskParams; aTaskCount: Integer);
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.Create','Enter  (%d)',[aTaskCount]);{$ENDIF USE_THREADLOG}
  inherited Create(aParams);
  FTaskCount:=aTaskCount;
  if FTaskCount<0 then
    FTaskCount:=2*TThread.ProcessorCount;
  {$IFDEF USE_THREADLOG}ThreadLog('TReplicableTask.Create','Leave');{$ENDIF USE_THREADLOG}
end;

{ *********************************************************************
  TProcJoinTask
  *********************************************************************}

procedure TProcJoinTask.JoinTasks;

var
  Proc : TParallel.TInt32Proc;
  Loop : TParallel.TInt32LoopProc;

begin
  Proc:=Procedure(aIndex : Integer)
    begin
      FProcList[aIndex];
    end;
  Loop:=TParallel.TInt32LoopProc.create(0,Length(FProcList)-1,Proc);
  TParallel.Parallelize32(Loop,Self.ThreadPool);
end;

constructor TProcJoinTask.Create(const AProcs: array of TProcRef; APool: TThreadPool);

var
  I,Len : integer;
  Params : TTaskParams;

begin
  // Copy procs
  Len:=Length(aProcs);
  SetLength(FProcList,Len);
  For I:=0 to Len-1 do
    FProcList[I]:=aProcs[i];
  Params.Proc:=@JoinTasks;
  Params.Parent:=Self;
  Params.Pool:=aPool;
  Inherited Create(Params);
end;


{ *********************************************************************
  TParallel
  *********************************************************************}

class function TParallel.Parallelize32(aLoop: TInt32LoopProc; aPool: TThreadPool): TLoopResult;


var
  LoopParams : TInt32LoopParams;
  LoopI : ILoopParams;
  TaskParams : TTask.TTaskParams;
  ControlFlag: TThreadPool.IControlFlag;
  aTask : ITask;

begin
  Result:=TLoopResult.Create;
  With aLoop do
    if HighExclusive<=LowInclusive then
      Exit;
  aLoop.Index:=aLoop.LowInclusive;
  if aLoop.Stride<=0 then
    aLoop.Stride:=1;
  ControlFlag:=Nil;
  if TTask.CurrentTask <> nil then
    ControlFlag:=(TTask.CurrentTask as TAbstractTask.IInternalTask).GetControlFlag;
  LoopParams:=TInt32LoopParams.Create(aLoop);
  LoopI:=LoopParams;
  try
    TaskParams:=Default(TTask.TTaskParams);
    TaskParams.ParentControlFlag:=ControlFlag;
    TaskParams.Pool:=aPool;
    TaskParams.CreateFlags:=[TTask.TCreateFlag.Replicating];
    TaskParams.Proc:=LoopParams;
    LoopI.CreateRootTask(TaskParams,aLoop.NumTasks);
    try
      aTask:=LoopI.StartLoop;
      aTask.Wait;
    except
      LoopI.HandleException;
    end;
    With Result do
      begin
      FCompleted:=LoopParams.StateFlags=[];
      if not FCompleted then
        FLowestBreakIteration:=LoopParams.BreakAt
      end
  finally
    LoopI.ClearRootTask; // Root task holds a reference to the loop. We need to free the root task.
    TaskParams.Proc:=Nil;
    LoopI:=Nil;
    aTask:=nil;
    LoopParams:=nil;
  end;
end;


class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent; aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent): TLoopResult;

begin
  Result:=&For(aSender,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent): TLoopResult;
begin
  Result:=&For(aSender,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorEvent
  ): TLoopResult;
begin
  Result:=&For(aSender,aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer;
  aIteratorEvent: TIteratorStateEvent; aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TIteratorStateEvent
  ): TLoopResult;
begin
  Result:=&For(aSender,aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;


class function TParallel.&For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger; aPool: TThreadPool
  ): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger): TLoopResult;
begin
  Result:=&For(aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;


class function TParallel.&For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;
begin
  aLoop:=TInt32LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState): TLoopResult;
begin
  Result:=&For(aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;


class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger; aPool: TThreadPool): TLoopResult;

var
  aLoop: TInt32LoopProc;

begin
  aLoop:=TInt32LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcInteger): TLoopResult;

begin
  Result:=&For(aStride, aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt32LoopProc;

begin
  aLoop:=TInt32LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize32(aLoop,aPool);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TProcIntegerLoopState): TLoopResult;
begin
  Result:=&For(aStride, aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;


{$IFDEF THREAD64BIT}

class function TParallel.Parallelize64(aLoop: TInt64LoopProc; aPool: TThreadPool): TLoopResult;

var
  LoopParams : TInt64LoopParams;
  LoopI : ILoopParams;
  TaskParams : TTask.TTaskParams;
  ControlFlag: TThreadPool.IControlFlag;
  aTask : ITask;

begin
  Result:=TLoopResult.Create;
  With aLoop do
    if HighExclusive<=LowInclusive then
      Exit;
  aLoop.Index:=aLoop.LowInclusive;
  if aLoop.Stride<=0 then
    aLoop.Stride:=1;
  ControlFlag:=Nil;
  if TTask.CurrentTask <> nil then
    ControlFlag:=(TTask.CurrentTask as TAbstractTask.IInternalTask).GetControlFlag;
  LoopParams:=TInt64LoopParams.Create(aLoop);
  LoopI:=LoopParams;
  try
    TaskParams:=Default(TTask.TTaskParams);
    TaskParams.ParentControlFlag:=ControlFlag;
    TaskParams.Pool:=aPool;
    TaskParams.CreateFlags:=[TTask.TCreateFlag.Replicating];
    TaskParams.Proc:=LoopParams;
    LoopI.CreateRootTask(TaskParams,aLoop.NumTasks);
    try
      aTask:=LoopI.StartLoop;
      aTask.Wait;
    except
      LoopI.HandleException;
    end;
    With Result do
      begin
      FCompleted:=LoopParams.StateFlags=[];
      if not FCompleted then
        FLowestBreakIteration:=LoopParams.BreakAt
      end
  finally
    LoopI.ClearRootTask; // Root task holds a reference to the loop. We need to free the root task.
    TaskParams.Proc:=Nil;
    LoopI:=Nil;
    aTask:=nil;
    LoopParams:=nil;
  end;
end;


class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64
  ): TLoopResult;
begin
  Result:=&For(aSender,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64): TLoopResult;
begin
  Result:=&For(aSender,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorEvent64
  ): TLoopResult;
begin
  Result:=&For(aSender,aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;


class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64;
  aIteratorEvent: TIteratorStateEvent64; aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aSender,aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aSender: TObject; aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TIteratorStateEvent64
  ): TLoopResult;
begin
  Result:=&For(aSender,aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64; aPool: TThreadPool
  ): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64): TLoopResult;
begin
  Result:=&For(aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState; aPool: TThreadPool
  ): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState): TLoopResult;
begin
  Result:=&For(aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64; aPool: TThreadPool): TLoopResult;

var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64): TLoopResult;
begin
  Result:=&For(aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState;
  aPool: TThreadPool): TLoopResult;
var
  aLoop: TInt64LoopProc;
begin
  aLoop:=TInt64LoopProc.Create(aLowInclusive,aHighInclusive,aIteratorEvent);
  aLoop.Stride:=aStride;
  Result:=Parallelize64(aLoop,aPool);
end;

class function TParallel.&For(aStride, aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TProcInt64LoopState
  ): TLoopResult;
begin
  Result:=&For(aStride,aLowInclusive,aHighInclusive,aIteratorEvent,TThreadPool.Default);
end;
{$ENDIF}

class function TParallel.Join(aSender: TObject; aEvents: array of TNotifyEvent; aPool: TThreadPool): ITask;
begin
  Result:=TEventJoinTask.Create(aSender,aEvents,aPool);
end;

class function TParallel.Join(const aProcs: array of TProcRef; aPool: TThreadPool): ITask;
begin
  Result:=TProcJoinTask.Create(aProcs,aPool);
end;

class function TParallel.Join(aSender: TObject; aEvents: array of TNotifyEvent): ITask;
begin
  Result:=Join(aSender,aEvents,TThreadPool.Default);
end;

class function TParallel.Join(aSender: TObject; aEvent1, aEvent2: TNotifyEvent; aPool: TThreadPool): ITask;
begin
  Result:=Join(aSender,[aEvent1,aEvent2],aPool);
end;

class function TParallel.Join(aSender: TObject; aEvent1, aEvent2: TNotifyEvent): ITask;
begin
  Result:=Join(aSender,aEvent1,aEvent2,TThreadPool.Default);
end;

class function TParallel.Join(const aProcs: array of TProcRef): ITask;
begin
  Result:=Join(aProcs,TThreadPool.Default);
end;

class function TParallel.Join(const aProc1, aProc2: TProcRef; aPool: TThreadPool): ITask;

begin
  Result:=Join([aProc1,aProc2],aPool);
end;

class function TParallel.Join(const aProc1, aProc2: TProcRef): ITask;
begin
  Result:=Join([aProc1,aProc2],TThreadPool.Default);
end;

{ *********************************************************************
  TParallel.TLoopState
  *********************************************************************}

constructor TParallel.TLoopState.Create(LoopParams : TLoopStateFlag);
begin
  FLoopParams:=LoopParams;
end;

function TParallel.TLoopState.GetStopped: Boolean;
begin
  Result:=FLoopParams.Stopped;
end;

function TParallel.TLoopState.GetFaulted: Boolean;
begin
  Result:=FLoopParams.Faulted;
end;

function TParallel.TLoopState.GetLowestBreakIteration: Variant;
begin
  Result:=DoGetLowestBreakIteration;
end;


function TParallel.TLoopState.DoGetLowestBreakIteration: Variant;
begin
  Result:=FLoopParams.GetBreakAt;
end;

procedure TParallel.TLoopState.Break;
begin
  DoBreak;
end;

procedure TParallel.TLoopState.Stop;
begin
  FLoopParams.Stop;
end;

function TParallel.TLoopState.ShouldExit: Boolean;
begin
  Result:=DoShouldExit;
end;

{ *********************************************************************
  TParallel.TLoopState32
  *********************************************************************}

constructor TParallel.TLoopState32.Create(aParams: TInt32LoopParams);
begin
  Inherited Create(aParams);
end;

procedure TParallel.TLoopState32.DoBreak;

begin
  // update state
  if not FLoopParams.Break then
    exit;
  TInt32LoopParams(FLoopParams).UpdateBreakAt(CurrentIteration);
end;

function TParallel.TLoopState32.DoShouldExit: Boolean;
begin
  Result:=TInt32LoopParams(FLoopParams).ShouldExitLoop(CurrentIteration);
end;

{ *********************************************************************
  TParallel.TLoopState64
  *********************************************************************}
{$IFDEF THREAD64BIT}
constructor TParallel.TLoopState64.Create(aParams: TInt64LoopParams);
begin
  Inherited Create(aParams);
end;

procedure TParallel.TLoopState64.DoBreak;

begin
  // update state
  if not FLoopParams.Break then
    exit;
  TInt64LoopParams(FLoopParams).UpdateBreakAt(CurrentIteration);
end;

function TParallel.TLoopState64.DoShouldExit: Boolean;
begin
  Result:=TInt64LoopParams(FLoopParams).ShouldExitLoop(CurrentIteration);
end;
{$ENDIF}


{ *********************************************************************
  TInt32LoopParams
  *********************************************************************}


procedure TParallel.TInt32LoopParams.UpdateBreakAt(aValue: Integer);
begin
  Lock;
  try
    if aValue<FBreakAt then
      FBreakAt:=aValue;
  finally
    Unlock;
  end;
end;

function TParallel.TInt32LoopParams.GetBreakAt: Variant;
begin
  Result:=FBreakAt;
end;

function TParallel.TInt32LoopParams.GetCurrentStride: Integer;
begin
  Result:=Stride
end;

function TParallel.TInt32LoopParams.GetNextStride: Integer;

Var
  NewValue : Integer;
  NextOK,MaxReached : Boolean;

begin
  Result:=GetCurrentStride;
  MaxReached:=(Result>=FMaxStride);
  NextOK:=(AtomicIncrement(FStrideCount) mod FNextStrideAt) = 0;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetNextStride','Current: %d, Count: %d, nextat: %d',[Result, FStrideCount, FNextStrideAt]);{$ENDIF USE_THREADLOG}
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetNextStride','if %s or not %s then',[BToS(MaxReached), BToS(NextOK)]);{$ENDIF USE_THREADLOG}
  if MaxReached  or Not NextOK then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetNextStride','Early exit');{$ENDIF USE_THREADLOG}
    exit;
    end;
  NewValue:=Result*2;
  if (NewValue>FMaxStride) then
    NewValue:=FMaxStride;
  // Only get new value if old did not change
  AtomicCmpExchange(FLoopProc.Stride,NewValue,Result);
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetNextStride','Result: %d',[Result]);{$ENDIF USE_THREADLOG}
end;

function TParallel.TInt32LoopParams.ShouldExitLoop: Boolean;
var
  Flags: TLoopStateFlagSet;

begin
  Result:=False;
  Flags:=StateFlags;
  If (Flags=[]) then
    exit;
  If (Flags*ShouldExitFlags)<>[] then
    Exit(True);
end;


function TParallel.TInt32LoopParams.ShouldExitLoop(CurrentIter : Integer): Boolean;

begin
  Result:=False;
  Result:=ShouldExitLoop;
  if Result then
    exit;
  Result:=(TLoopStateFlag.Broken in StateFlags) and (CurrentIter>FBreakAt);
end;



function TParallel.TInt32LoopParams.GetCurrentStart(out aStride: Integer): Integer;
begin
  aStride:=GetCurrentStride;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetCurrentStart','Index: %d, Stride: %d',[FLoopProc.Index,aStride]);{$ENDIF USE_THREADLOG}
  Result:=TInterlocked.Add(FLoopProc.Index,aStride)-aStride;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.GetCurrentStart','Result : %d',[Result]);{$ENDIF USE_THREADLOG}
end;

constructor TParallel.TInt32LoopParams.Create(aLoopProc: TInt32LoopProc);
begin
  FLoopProc:=aLoopProc;
  FNextStrideAt:=TThread.ProcessorCount;
  FBreakAt:=aLoopProc.HighExclusive+1;
  FMaxStride:=FNextStrideAt*16; // 16 loops max
end;

destructor TParallel.TInt32LoopParams.Destroy;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Destroy','Enter (%d)',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
  inherited Destroy;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Destroy','Leave (%d)',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
end;

procedure TParallel.TInt32LoopParams.Invoke;

var
  I, Start, Limit, UpperLimit, MyStride: Integer;
  LoopState: TLoopState32;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Enter');{$ENDIF USE_THREADLOG}
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Loop params: '+Self.FLoopProc.ToString);{$ENDIF USE_THREADLOG}
  LoopState:=nil;
  if Assigned(FLoopProc.ProcWithState) or Assigned(FLoopProc.StateEvent) then
    LoopState:=TLoopState32.Create(Self);
  try
    UpperLimit:=HighExclusive;
    Start:=GetCurrentStart(MyStride);
    {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Start: %d, Upper: %d, Stride: %d',[Start,UpperLimit,MyStride]);{$ENDIF USE_THREADLOG}
    while Start<UpperLimit do
      begin
      I:=Start;
      Limit:=Start+MyStride;
      If Limit>UpperLimit then
        Limit:=UpperLimit;
      {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Inner loop from %d to Limit: %d',[I,Limit]);{$ENDIF USE_THREADLOG}
      while (I<Limit) and not ShouldExitLoop(I) do
        begin
        {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Executing loop at %d',[I]);{$ENDIF USE_THREADLOG}
        FLoopProc.Execute(I,LoopState);
        Inc(I);
        end;
      if ShouldExitLoop(Start) then
        Break;
      GetNextStride;
      Start:=GetCurrentStart(MyStride);
      {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','Next loop from %d to %d',[Start,Start+MyStride]);{$ENDIF USE_THREADLOG}
      end;
  finally
    LoopState.Free;
  end;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopParams.Invoke','leave');{$ENDIF USE_THREADLOG}
end;


{ *********************************************************************
  TInt64LoopParams
  *********************************************************************}

{$IFDEF THREAD64BIT}

procedure TParallel.TInt64LoopParams.UpdateBreakAt(aValue: Int64);
begin
  Lock;
  try
    if aValue<FBreakAt then
      FBreakAt:=aValue;
  finally
    Unlock;
  end;
end;

function TParallel.TInt64LoopParams.GetBreakAt: Variant;
begin
  Result:=FBreakAt;
end;

function TParallel.TInt64LoopParams.GetCurrentStride: Int64;
begin
  Result:=Stride
end;

function TParallel.TInt64LoopParams.GetNextStride: Int64;

Var
  NewValue : Int64;
  NextOK,MaxReached : Boolean;

begin
  Result:=GetCurrentStride;
  MaxReached:=(Result>=FMaxStride);
  NextOK:=(AtomicIncrement(FStrideCount) mod FNextStrideAt) = 0;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetNextStride','Current: %d, Count: %d, nextat: %d',[Result, FStrideCount, FNextStrideAt]);{$ENDIF USE_THREADLOG}
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetNextStride','if %s or not %s then',[BToS(MaxReached), BToS(NextOK)]);{$ENDIF USE_THREADLOG}
  if MaxReached  or Not NextOK then
    begin
    {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetNextStride','Early exit');{$ENDIF USE_THREADLOG}
    exit;
    end;
  NewValue:=Result*2;
  if (NewValue>FMaxStride) then
    NewValue:=FMaxStride;
  // Only get new value if old did not change
  AtomicCmpExchange(FLoopProc.Stride,NewValue,Result);
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetNextStride','Result: %d',[Result]);{$ENDIF USE_THREADLOG}
end;

function TParallel.TInt64LoopParams.ShouldExitLoop: Boolean;
var
  Flags: TLoopStateFlagSet;

begin
  Result:=False;
  Flags:=StateFlags;
  If (Flags=[]) then
    exit;
  If (Flags*ShouldExitFlags)<>[] then
    Exit(True);
end;


function TParallel.TInt64LoopParams.ShouldExitLoop(CurrentIter : Int64): Boolean;

begin
  Result:=False;
  Result:=ShouldExitLoop;
  if Result then
    exit;
  Result:=(TLoopStateFlag.Broken in StateFlags) and (CurrentIter>FBreakAt);
end;



function TParallel.TInt64LoopParams.GetCurrentStart(out aStride: Int64): Int64;
begin
  aStride:=GetCurrentStride;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetCurrentStart','Index: %d, Stride: %d',[FLoopProc.Index,aStride]);{$ENDIF USE_THREADLOG}
  Result:=TInterlocked.Add(FLoopProc.Index,aStride)-aStride;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.GetCurrentStart','Result : %d',[Result]);{$ENDIF USE_THREADLOG}
end;

constructor TParallel.TInt64LoopParams.Create(aLoopProc: TInt64LoopProc);
begin
  FLoopProc:=aLoopProc;
  FNextStrideAt:=TThread.ProcessorCount;
  FBreakAt:=aLoopProc.HighExclusive+1;
  FMaxStride:=FNextStrideAt*16; // 16 loops max
end;

destructor TParallel.TInt64LoopParams.Destroy;
begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Destroy','Enter (%d)',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
  inherited Destroy;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Destroy','Leave (%d)',[PtrInt(Self)]);{$ENDIF USE_THREADLOG}
end;

procedure TParallel.TInt64LoopParams.Invoke;

var
  I, Start, Limit, UpperLimit, MyStride: Int64;
  LoopState: TLoopState64;

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Enter');{$ENDIF USE_THREADLOG}
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Loop params: '+Self.FLoopProc.ToString);{$ENDIF USE_THREADLOG}
  LoopState:=nil;
  if Assigned(FLoopProc.ProcWithState) or Assigned(FLoopProc.StateEvent) then
    LoopState:=TLoopState64.Create(Self);
  try
    UpperLimit:=HighExclusive;
    Start:=GetCurrentStart(MyStride);
    {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Start: %d, Upper: %d, Stride: %d',[Start,UpperLimit,MyStride]);{$ENDIF USE_THREADLOG}
    while Start<UpperLimit do
      begin
      I:=Start;
      Limit:=Start+MyStride;
      If Limit>UpperLimit then
        Limit:=UpperLimit;
      {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Inner loop from %d to Limit: %d',[I,Limit]);{$ENDIF USE_THREADLOG}
      while (I<Limit) and not ShouldExitLoop(I) do
        begin
        {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Executing loop at %d',[I]);{$ENDIF USE_THREADLOG}
        FLoopProc.Execute(I,LoopState);
        Inc(I);
        end;
      if ShouldExitLoop(Start) then
        Break;
      GetNextStride;
      Start:=GetCurrentStart(MyStride);
      {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','Next loop from %d to %d',[Start,Start+MyStride]);{$ENDIF USE_THREADLOG}
      end;
  finally
    LoopState.Free;
  end;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopParams.Invoke','leave');{$ENDIF USE_THREADLOG}
end;

{$ENDIF}

{ *********************************************************************
  TParallel.TInt32LoopProc
  *********************************************************************}

procedure TParallel.TInt32LoopProc.Execute(Iteration: Integer; aState: TLoopState32);

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopProc.Execute','enter (%d)',[Iteration]);{$ENDIF USE_THREADLOG}
  //       This would make it so that only a single virtual call is made to process the iterations.
  if Assigned(Event) then
    Event(Sender, Iteration)
  else if Assigned(Proc) then
    Proc(Iteration)
  else if Assigned(ProcWithState) then
  begin
    aState.CurrentIteration:=Iteration;
    ProcWithState(Iteration,aState);
  end
  else if Assigned(StateEvent) then
  begin
    aState.CurrentIteration:=Iteration;
    StateEvent(Sender,Iteration,aState);
  end;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt32LoopProc.Execute','leave (%d) ',[Iteration]);{$ENDIF USE_THREADLOG}
end;

function TParallel.TInt32LoopProc.NumTasks: Integer;

var
  aMax : Integer;

begin
  Result:=HighExclusive-LowInclusive;
  aMax:=TThread.ProcessorCount*2;
  if Result>aMax then
    Result:=aMax;
end;

class function TParallel.TInt32LoopProc.create(aSender: TObject; aLowInclusive, aHighInclusive: Integer;
  aIteratorEvent: TIteratorEvent32): TParallel.TInt32LoopProc;
begin
  Result:=Default(TInt32LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Sender:=aSender;
  Result.Event:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt32LoopProc.create(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TInt32Proc
  ): TParallel.TInt32LoopProc;
begin
  Result:=Default(TInt32LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Proc:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt32LoopProc.create(aSender: TObject; aLowInclusive, aHighInclusive: Integer;
  aIteratorEvent: TIteratorStateEvent32): TParallel.TInt32LoopProc;
begin
  Result:=Default(TInt32LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Sender:=aSender;
  Result.StateEvent:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt32LoopProc.create(aLowInclusive, aHighInclusive: Integer; aIteratorEvent: TInt32LoopStateProc): TParallel.TInt32LoopProc;
begin
  Result:=Default(TInt32LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.ProcWithState:=aIteratorEvent;
  Result.Stride:=-1;
end;

function TParallel.TInt32LoopProc.ToString: String;
begin
  Result:=Format('loop from %d to %d with step %d currently at %d',[LowInclusive,HighExclusive,Stride,Index]);
end;

{ *********************************************************************
  TParallel.TInt64LoopProc
  *********************************************************************}

{$IFDEF THREAD64BIT}

procedure TParallel.TInt64LoopProc.Execute(Iteration: Int64; aState: TLoopState64);

begin
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopProc.Execute','enter (%d)',[Iteration]);{$ENDIF USE_THREADLOG}
  //       This would make it so that only a single virtual call is made to process the iterations.
  if Assigned(Event) then
    Event(Sender, Iteration)
  else if Assigned(Proc) then
    Proc(Iteration)
  else if Assigned(ProcWithState) then
  begin
    aState.CurrentIteration:=Iteration;
    ProcWithState(Iteration,aState);
  end
  else if Assigned(StateEvent) then
  begin
    aState.CurrentIteration:=Iteration;
    StateEvent(Sender,Iteration,aState);
  end;
  {$IFDEF USE_THREADLOG}ThreadLog('TParallel.TInt64LoopProc.Execute','leave (%d) ',[Iteration]);{$ENDIF USE_THREADLOG}
end;

function TParallel.TInt64LoopProc.NumTasks: Integer;

var
  aMax : Integer;

begin
  Result:=HighExclusive-LowInclusive;
  aMax:=TThread.ProcessorCount*2;
  if Result>aMax then
    Result:=aMax;
end;

class function TParallel.TInt64LoopProc.create(aSender: TObject; aLowInclusive, aHighInclusive: Int64;
  aIteratorEvent: TIteratorEvent64): TParallel.TInt64LoopProc;
begin
  Result:=Default(TInt64LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Sender:=aSender;
  Result.Event:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt64LoopProc.create(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TInt64Proc
  ): TParallel.TInt64LoopProc;
begin
  Result:=Default(TInt64LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Proc:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt64LoopProc.create(aSender: TObject; aLowInclusive, aHighInclusive: Int64;
  aIteratorEvent: TIteratorStateEvent64): TParallel.TInt64LoopProc;
begin
  Result:=Default(TInt64LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.Sender:=aSender;
  Result.StateEvent:=aIteratorEvent;
  Result.Stride:=-1;
end;

class function TParallel.TInt64LoopProc.create(aLowInclusive, aHighInclusive: Int64; aIteratorEvent: TInt64LoopStateProc): TParallel.TInt64LoopProc;
begin
  Result:=Default(TInt64LoopProc);
  Result.LowInclusive:=aLowInclusive;
  Result.HighExclusive:=aHighInclusive+1;
  Result.ProcWithState:=aIteratorEvent;
  Result.Stride:=-1;
end;

function TParallel.TInt64LoopProc.ToString: String;
begin
  Result:=Format('loop from %d to %d with step %d currently at %d',[LowInclusive,HighExclusive,Stride,Index]);
end;

{$ENDIF}

{ *********************************************************************
  TParallel.TLoopParams
  *********************************************************************}

function TParallel.TLoopParams.StartLoop: ITask;
begin
  Result:=FRootTask.Start;
end;

procedure TParallel.TLoopParams.CreateRootTask(aParams: TTask.TTaskParams; aCount: Integer);
begin
  FRootTask:=TReplicableTask.Create(aParams,aCount);
end;

procedure TParallel.TLoopParams.ClearRootTask;
begin
  FRootTask:=Nil;
end;

procedure TParallel.TLoopParams.Stop;
begin
  Lock;
  Try
    Include(StateFlags,TLoopStateFlag.Stopped);
  finally
    UnLock;
  end;
end;

function TParallel.TLoopParams.Break: Boolean;
begin
  Result:=False;
  lock;
  try
    if TLoopStateFlag.Stopped in StateFlags then
      raise EInvalidOperation.Create(SErrBreakAfterStop);
    if (StateFlags*[TLoopStateFlag.Exception, TLoopStateFlag.Cancelled])<>[] then
      Exit(False);
    Include(StateFlags,TLoopStateFlag.Broken);
    Result:=True;
  finally
    UnLock
  end;
end;

function TParallel.TLoopParams.Stopped: Boolean;
begin
  Result:=TLoopStateFlag.Stopped in StateFlags;
end;

function TParallel.TLoopParams.Faulted: Boolean;
begin
  Result:=TLoopStateFlag.Exception in StateFlags;
end;

constructor TParallel.TLoopParams.Create;
begin
  FStateLock:=TSpinLock.Create(False);
end;

destructor TParallel.TLoopParams.Destroy;
begin
  inherited Destroy;
end;

procedure TParallel.TLoopParams.Lock;
begin
  FStateLock.Enter;
end;

procedure TParallel.TLoopParams.UnLock;
begin
  FStateLock.Exit;
end;

procedure TParallel.TLoopParams.HandleException(O: TObject);

var
  E : Exception absolute O;
  ErrorTasks : TTaskArray;
  ExcList : TExceptionList;
  aTask: TTask;


begin
  if not (O is Exception) then
    begin
    O.Free;
    exit;
    end;
  Lock;
  try
    ErrorTasks:=(FRootTask as TTask).FTasksWithExceptions;
    if not assigned(ErrorTasks) then
      raise E;
    ExcList:=TExceptionList.Create(E,Length(ErrorTasks)+1);
    for aTask in ErrorTasks do
      ExcList.AddFromTask(aTask);
  finally
    Unlock;
  end;
  raise EAggregateException.Create(ExcList.Truncate);
end;

procedure TParallel.TLoopParams.HandleException;
begin
  HandleException(TObject(AcquireExceptionObject));
end;

{ *********************************************************************
  TParallel.TLoopResult
  *********************************************************************}

class function TParallel.TLoopResult.Create: TLoopResult;
begin
  Result:=Default(TLoopResult);
  Result.FCompleted:=True;
  Result.FLowestBreakIteration:=NULL;
end;

{ *********************************************************************
  Auxiliary
  *********************************************************************}

Procedure InitThreading;

begin
  // Caches needs to exist before they can be used to register objects
  // We don't know the order of class constructors, so we do it manually here
  TThreadPool.Caches:=TObjectCaches.Create([doOwnsValues]);
  TThreadPool.Caches.AddObjectCache(TTask);
  TThreadPool.Caches.AddObjectCache(TReplicableTask);
  TThreadPool.Caches.AddObjectCache(TReplicatedTask);
  TThreadPool.FDefaultPool:=TThreadPool.Create;
end;

Procedure DoneThreading;
begin
  FreeAndNil(TThreadPool.FDefaultPool);
  FreeAndNil(TThreadPool.Caches);
end;

Initialization
  InitThreading;
Finalization
  DoneThreading;
end.
