unit UnitNiveis.Model;

interface

uses
	System.SysUtils,
	System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  UnitPortalORM.Model, UnitDatabase;

type
	[TNomeTabela('OPCOES', 'OP_CODIGO')]
  TOpcao = class(TTabela)
  private
    FCodigo: Integer;
    FNome: string;
    FValorAdicional: Double;
    FAtivo: Boolean;
    FAtivoStr: string;
    FCodNivel: integer;
    procedure SetAtivoStr(const Value: string);
  public
  	[TCampo('OP_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: Integer read FCodigo write FCodigo;
    [TCampo('OP_NOME', 'VARCHAR(200)')]
    property Nome: string read FNome write FNome;
    [TCampo('OP_NI', 'INTEGER NOT NULL REFERENCES NIVEIS(NI_CODIGO)')]
    property CodNivel: integer read FCodNivel write FCodNivel;
    [TCampo('OP_VALOR', 'NUMERIC(12,4)')]
    property ValorAdicional: Double read FValorAdicional write FValorAdicional;
    [TCampo('OP_ATIVO', 'CHAR(1)')]
    property AtivoStr: string read FAtivoStr write SetAtivoStr;
    property Ativo: Boolean read FAtivo write FAtivo;
  end;

  [TNomeTabela('NIVEIS', 'NI_CODIGO')]
  TNivel = class(TTabela)
  private
    FCodigo: Integer;
    FTitulo: string;
    FDescricao: string;
    FSelecaoMin: Integer;
    FSelecaoMax: Integer;
    FOpcoes: TArray<TOpcao>;
    FCodProduto: integer;
    procedure SetCodigo(const Value: Integer);
  public
    constructor Create; overload;
    destructor Destroy; override;
    [TCampo('NI_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: Integer read FCodigo write SetCodigo;
    [TCampo('NI_TITULO', 'VARCHAR(200)')]
    property Titulo: string read FTitulo write FTitulo;
    [TCampo('NI_PRO', 'INTEGER NOT NULL REFERENCES PRODUTOS(PRO_CODIGO)')]
    property CodProduto: integer read FCodProduto write FCodProduto;
    [TCampo('NI_DESCRICAO', 'VARCHAR(200)')]
    property Descricao: string read FDescricao write FDescricao;
    [TCampo('NI_SELECAO_MIN', 'INTEGER')]
    property SelecaoMin: Integer read FSelecaoMin write FSelecaoMin;
    [TCampo('NI_SELECAO_MAX', 'INTEGER')]
    property SelecaoMax: Integer read FSelecaoMax write FSelecaoMax;
    property Opcoes: TArray<TOpcao> read FOpcoes write FOpcoes;
  end;

implementation

uses
	UnitTabela.Helpers;

{ TNivel }

constructor TNivel.Create;
begin
	inherited Create(TDatabase.Connection);
end;

destructor TNivel.Destroy;
begin
  inherited;
end;

procedure TNivel.SetCodigo(const Value: Integer);
var
  ListaOpcoes: TList<TOpcao>;
  Opcao: TOpcao;
begin
	FCodigo := Value;
	// cria objeto
  Opcao := TOpcao.Create(TDatabase.Connection);
  Opcao.CriaTabela;
	// busca opções
  ListaOpcoes := Opcao.PreencheListaWhere<TOpcao>('OP_ATIVO = ''S'' AND OP_NI='+Value.ToString, 'OP_CODIGO');
  FOpcoes := ListaOpcoes.ToArray;
end;

{ TOpcao }

procedure TOpcao.SetAtivoStr(const Value: string);
begin
  FAtivoStr := Value;
  FAtivo := FAtivoStr.ToUpper.Contains('S');
end;

end.
