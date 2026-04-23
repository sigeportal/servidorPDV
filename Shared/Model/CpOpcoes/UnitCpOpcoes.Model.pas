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
    FNome: string;
    FValor: Currency;
    FAtivo: string;
    FCodNi: integer;
    FSelecionado: string;
    FQuantidade: double;
    FCp: integer;
    FcodOpcao: integer;
  public
    { public declarations }
    [TCampo('CO_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('CO_NOME', 'VARCHAR(100)')]
    property Nome: string read FNome write FNome;
    [TCampo('CO_CP', 'INTEGER')]
    property Cp: integer read FCp write FCp;
    [TCampo('CO_NI', 'INTEGER')]
    property CodNi: integer read FCodNi write FCodNi;
    [TCampo('CO_QUANTIDADE', 'NUMERIC(9,2)')]
    property Quantidade: double read FQuantidade write FQuantidade;
    [TCampo('CO_VALOR', 'NUMERIC(9,2)')]
    property Valor: Currency read FValor write FValor;
    [TCampo('CO_ATIVO', 'CHAR(1)')]
    property Ativo: string read FAtivo write FAtivo;
    [TCampo('CO_SELECIONADO', 'CHAR(1)')]
    property Selecionado: string read FSelecionado write FSelecionado; 
    [TCampo('CO_OP', 'INTEGER')]
    property codOpcao: integer read FcodOpcao write FcodOpcao;
  end;

implementation

end.
