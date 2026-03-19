unit UnitCpAdicionais.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/cpAdicionais')]
  [TNomeTabela('CP_ADICIONAIS', 'CA_CODIGO')]
  TCpAdicionais = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FCp: integer;
    FAdi: integer;
    FQuantidade: double;
  public
    { public declarations }
    [TCampo('CA_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('CA_CP', 'INTEGER')]
    property Cp: integer read FCp write FCp;
    [TCampo('CA_ADI', 'INTEGER')]
    property Adi: integer read FAdi write FAdi;
    [TCampo('CA_QUANTIDADE', 'NUMERIC(9,2)')]
    property Quantidade: double read FQuantidade write FQuantidade;
  end;

implementation

end.
