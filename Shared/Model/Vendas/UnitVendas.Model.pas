unit UnitVendas.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model,
  {$ELSE}
  UnitBancoDeDados.Model,
  {$ENDIF}
  System.SysUtils,
  UnitVenEst.Model, 
  UnitPedFat.Model, 
  System.Generics.Collections,
   UnitDatabase;

type
  [TRecursoServidor('/vendas')]
  [TNomeTabela('VENDAS', 'VEN_CODIGO')]
  TVendas = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FData: TDateTime;
    FValor: double;
    FHora: TTime;
    FFun: integer;
    FNf: integer;
    FDiferenca: double;
    FDatac: TDate;
    FFat: integer;
    FDav: integer;
    FCli: integer;
    FDevolucao_p: string;
    FTipo_pedido: string;
    FTaxa_entrega: double;
    FForma_pgto: integer;
    FNome_cliente: string;
    FId_pedido: string;
    FItens: TArray<TVenEst>;
    FPedFat: TPedFat;
//    procedure SetCodigo(const Value: integer);
  public
    destructor Destroy; override;    
    { public declarations }
    [TCampo('VEN_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('VEN_DATA', 'DATE')]
    property Data: TDateTime read FData write FData;
    [TCampo('VEN_VALOR', 'NUMERIC(9,2)')]
    property Valor: double read FValor write FValor;
    [TCampo('VEN_HORA', 'TIME')]
    property Hora: TTime read FHora write FHora;
    [TCampo('VEN_FUN', 'SMALLINT')]
    property Fun: integer read FFun write FFun;
    [TCampo('VEN_NF', 'INTEGER')]
    property Nf: integer read FNf write FNf;
    [TCampo('VEN_DIFERENCA', 'NUMERIC(9,2)')]
    property Diferenca: double read FDiferenca write FDiferenca;
    [TCampo('VEN_DATAC', 'DATE')]
    property Datac: TDate read FDatac write FDatac;
    [TCampo('VEN_FAT', 'INTEGER')]
    property Fat: integer read FFat write FFat;
    [TCampo('VEN_DAV', 'SMALLINT')]
    property Dav: integer read FDav write FDav;
    [TCampo('VEN_CLI', 'INTEGER')]
    property Cli: integer read FCli write FCli;
    [TCampo('VEN_DEVOLUCAO_P', 'VARCHAR(1)')]
    property Devolucao_p: string read FDevolucao_p write FDevolucao_p;
    [TCampo('VEN_TIPO_PEDIDO', 'VARCHAR(10)')]
    property Tipo_pedido: string read FTipo_pedido write FTipo_pedido;
    [TCampo('VEN_TAXA_ENTREGA', 'NUMERIC(9,2)')]
    property Taxa_entrega: double read FTaxa_entrega write FTaxa_entrega;
    [TCampo('VEN_FORMA_PGTO', 'INTEGER')]
    property Forma_pgto: integer read FForma_pgto write FForma_pgto;
    [TCampo('VEN_NOME_CLIENTE', 'VARCHAR(100)')]
    property Nome_cliente: string read FNome_cliente write FNome_cliente;
    [TCampo('VEN_ID_PEDIDO', 'VARCHAR(500)')]
    property Id_pedido: string read FId_pedido write FId_pedido;
    property Itens: TArray<TVenEst> read FItens write FItens;
    property PedFat: TPedFat read FPedFat write FPedFat;
    function Clone: TVendas;
  end;

  TVendasResponse = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FData: TDate;
    FValor: double;
    FHora: TTime;
    FFun: integer;
    FNf: integer;
    FDiferenca: double;
    FDatac: TDate;
    FFat: integer;
    FDav: integer;
    FCli: integer;
    FDevolucao_p: string;
    FTipo_pedido: string;
    FTaxa_entrega: double;
    FForma_pgto: integer;
    FNome_cliente: string;
    FId_pedido: string;
    FItens: TObjectList<TVenEst>;
    FPedFat: TPedFatResponse;
  public
    { public declarations }
    property Codigo: integer read FCodigo write FCodigo;
    property Data: TDate read FData write FData;
    property Valor: double read FValor write FValor;
    property Hora: TTime read FHora write FHora;
    property Fun: integer read FFun write FFun;
    property Nf: integer read FNf write FNf;
    property Diferenca: double read FDiferenca write FDiferenca;
    property Datac: TDate read FDatac write FDatac;
    property Fat: integer read FFat write FFat;
    property Dav: integer read FDav write FDav;
    property Cli: integer read FCli write FCli;
    property Devolucao_p: string read FDevolucao_p write FDevolucao_p;
    property Tipo_pedido: string read FTipo_pedido write FTipo_pedido;
    property Taxa_entrega: double read FTaxa_entrega write FTaxa_entrega;
    property Forma_pgto: integer read FForma_pgto write FForma_pgto;
    property Nome_cliente: string read FNome_cliente write FNome_cliente;
    property Id_pedido: string read FId_pedido write FId_pedido;
    property Itens: TObjectList<TVenEst> read FItens write FItens;
    property PedFat: TPedFatResponse read FPedFat write FPedFat;
  end;

implementation

uses
  FireDAC.Comp.Client,
  UnitTabela.Helpers;

{ TVendas }

function TVendas.Clone: TVendas;
begin
  Result := TVendas.Create(TFDConnection(Self.IBQR.Connection));

  // Copia campos simples
  Result.Codigo        := Self.Codigo;
  Result.Data          := Self.Data;
  Result.Valor         := Self.Valor;
  Result.Hora          := Self.Hora;
  Result.Fun           := Self.Fun;
  Result.Nf            := Self.Nf;
  Result.Diferenca     := Self.Diferenca;
  Result.Datac         := Self.Datac;
  Result.Fat           := Self.Fat;
  Result.Dav           := Self.Dav;
  Result.Cli           := Self.Cli;
  Result.Devolucao_p   := Self.Devolucao_p;
  Result.Tipo_pedido   := Self.Tipo_pedido;
  Result.Taxa_entrega  := Self.Taxa_entrega;
  Result.Forma_pgto    := Self.Forma_pgto;
  Result.Nome_cliente  := Self.Nome_cliente;
  Result.Id_pedido     := Self.Id_pedido;  
end;

destructor TVendas.Destroy;
begin
//	if Assigned(FPedFat) then
//  	FPedFat.DisposeOf;
  inherited;
end;

//procedure TVendas.SetCodigo(const Value: integer);
//var
//  ListaItens: TList<TVenEst>;
//  i: Integer;
//begin
//  FCodigo := Value;
//  ListaItens := TVenEst.Create(TDatabase.Connection).PreencheListaWhere<TVenEst>('VE_VEN='+FCodigo.toString, 'VE_CODIGO');
//  try
//    FItens := ListaItens.ToArray;
//    //PED FAT 
//    FPedFat := TPedFat.Create(TDatabase.Connection);
//    FPedFat.BuscaPorCampo('PF_COD_PED', FCodigo);
//  finally
//    ListaItens.DisposeOf;
//  end;      
//end;

end.
