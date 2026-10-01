unit UnitNiveis.Model;

interface

uses
	System.SysUtils,
	System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  UnitPortalORM.Model, UnitDatabase, UnitConnection.Model.Interfaces;

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
  Opcao: TOpcao;
  Query: iQuery;
  ListaOpcoes: TList<TOpcao>;
begin
  FCodigo := Value;

  // Limpa o array anterior se já existir conteúdo, evitando memory leak
  if Length(FOpcoes) > 0 then
  begin
    for Opcao in FOpcoes do
      Opcao.DisposeOf; // ou Opcao.Free
    SetLength(FOpcoes, 0);
  end;

  ListaOpcoes := TList<TOpcao>.Create;
  try
    Query := TDatabase.Query;
    Query.Add('SELECT OP_CODIGO, OP_NOME, OP_NI, OP_VALOR, OP_ATIVO ');
    Query.Add('FROM OPCOES ');
    Query.Add('WHERE OP_NI = :NIVEL AND OP_ATIVO = ''S'' ');
    Query.Add('ORDER BY OP_CODIGO');
    Query.AddParam('NIVEL', Value);
    Query.Open();
    while not Query.DataSet.Eof do
    begin
      Opcao := TOpcao.Create(TDatabase.Connection);
      // Preenche as propriedades diretamente com a query já aberta
      Opcao.Codigo := Query.DataSet.FieldByName('OP_CODIGO').AsInteger;
      Opcao.Nome   := Query.DataSet.FieldByName('OP_NOME').AsString;
      Opcao.CodNivel  := Query.DataSet.FieldByName('OP_NI').AsInteger;
      Opcao.ValorAdicional  := Query.DataSet.FieldByName('OP_VALOR').AsCurrency;
      Opcao.AtivoStr  := Query.DataSet.FieldByName('OP_ATIVO').AsString;
      Opcao.Ativo  := Query.DataSet.FieldByName('OP_ATIVO').AsString = 'S';
      ListaOpcoes.Add(Opcao);
      Query.DataSet.Next;
    end;
    FOpcoes := ListaOpcoes.ToArray;
  finally
    ListaOpcoes.Free; // Libera a lista da memória (os objetos continuam no array FOpcoes)
  end;
end;

{ TOpcao }

procedure TOpcao.SetAtivoStr(const Value: string);
begin
  FAtivoStr := Value;
  FAtivo := FAtivoStr.ToUpper.Contains('S');
end;

end.
