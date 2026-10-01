unit UnitAdicionais.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/adicionais')]
  [TNomeTabela('ADICIONAIS', 'ADI_CODIGO')]
  TAdicionais = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FNome: string;
    FValor: double;
    FEstado: string;
    FG1: integer;
  public
    { public declarations }
    [TCampo('ADI_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('ADI_NOME', 'VARCHAR(100)')]
    property Nome: string read FNome write FNome;
    [TCampo('ADI_VALOR', 'NUMERIC(12,4)')]
    property Valor: double read FValor write FValor;
    [TCampo('ADI_ESTADO', 'VARCHAR(10)')]
    property Estado: string read FEstado write FEstado;
    [TCampo('ADI_G1', 'INTEGER')]
    property G1: integer read FG1 write FG1;
  end;

implementation

end.
