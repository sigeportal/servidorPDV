unit UnitGrades.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/grades')]
  [TNomeTabela('GRADES', 'GRA_CODIGO')]
  TGrades = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FPro: integer;
    FValor: double;
    FTam: integer;
  public
    { public declarations }
    [TCampo('GRA_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('GRA_PRO', 'INTEGER')]
    property Pro: integer read FPro write FPro;
    [TCampo('GRA_VALOR', 'NUMERIC(9,2)')]
    property Valor: double read FValor write FValor;
    [TCampo('GRA_TAM', 'INTEGER')]
    property Tam: integer read FTam write FTam;
  end;

implementation

end.
