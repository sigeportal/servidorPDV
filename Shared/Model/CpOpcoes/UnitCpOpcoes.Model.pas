unit UnitCpOpcoes.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/cpOpcoes')]
  [TNomeTabela('CP_OPCOES', 'CO_CODIGO')]
  TCpOpcoes = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FCp: integer;
    FQuantidade: double;
    FCodNi: integer;
    FValor: Currency;
  public
    { public declarations }
    [TCampo('CO_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('CO_CP', 'INTEGER')]
    property Cp: integer read FCp write FCp;
    [TCampo('CO_NI', 'INTEGER')]
    property CodNi: integer read FCodNi write FCodNi;
    [TCampo('CO_QUANTIDADE', 'NUMERIC(9,2)')]
    property Quantidade: double read FQuantidade write FQuantidade;
    [TCampo('CO_VALOR', 'NUMERIC(9,2)')]
    property Valor: Currency read FValor write FValor;
  end;

implementation

end.
