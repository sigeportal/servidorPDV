unit UnitVenEst.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model,
  {$ELSE}
  UnitBancoDeDados.Model,
  {$ENDIF}
  UnitDatabase, UnitVeAdicionais.Model, UnitVeOpcoes.Model;

type
  [TRecursoServidor('/venEst')]
  [TNomeTabela('VEN_EST', 'VE_CODIGO')]
  TVenEst = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FValor: double;
    FQuantidade: double;
    FVen: integer;
    FPro: integer;
    FLucro: double;
    FValorr: double;
    FValorl: double;
    FValorf: double;
    FDiferenca: double;
    FLiquido: integer;
    FValor2: double;
    FValorcm: double;
    FAliquota: double;
    FGtin: string;
    FEmbalagem: string;
    FValorb: double;
    FDesconto: double;
    FValorc: double;
    FObs: string;
    FGra: integer;
    FSemente_tratada: string;
    FValor_partida: double;
    FVariacao: double;
    FUsu: integer;
    FComplementos: TArray<TVeAdicionais>;
    FOpcoesNivel: TArray<TVeOpcoes>;    
  public
    { public declarations }
    [TCampo('VE_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('VE_VALOR', 'NUMERIC(9,4)')]
    property Valor: double read FValor write FValor;
    [TCampo('VE_QUANTIDADE', 'NUMERIC(9,4)')]
    property Quantidade: double read FQuantidade write FQuantidade;
    [TCampo('VE_VEN', 'INTEGER')]
    property Ven: integer read FVen write FVen;
    [TCampo('VE_PRO', 'INTEGER')]
    property Pro: integer read FPro write FPro;
    [TCampo('VE_LUCRO', 'NUMERIC(9,4)')]
    property Lucro: double read FLucro write FLucro;
    [TCampo('VE_VALORR', 'NUMERIC(9,4)')]
    property Valorr: double read FValorr write FValorr;
    [TCampo('VE_VALORL', 'NUMERIC(9,4)')]
    property Valorl: double read FValorl write FValorl;
    [TCampo('VE_VALORF', 'NUMERIC(9,4)')]
    property Valorf: double read FValorf write FValorf;
    [TCampo('VE_DIFERENCA', 'NUMERIC(9,4)')]
    property Diferenca: double read FDiferenca write FDiferenca;
    [TCampo('VE_LIQUIDO', 'SMALLINT')]
    property Liquido: integer read FLiquido write FLiquido;
    [TCampo('VE_VALOR2', 'NUMERIC(9,4)')]
    property Valor2: double read FValor2 write FValor2;
    [TCampo('VE_VALORCM', 'NUMERIC(9,4)')]
    property Valorcm: double read FValorcm write FValorcm;
    [TCampo('VE_ALIQUOTA', 'NUMERIC(5,2)')]
    property Aliquota: double read FAliquota write FAliquota;
    [TCampo('VE_GTIN', 'VARCHAR(14)')]
    property Gtin: string read FGtin write FGtin;
    [TCampo('VE_EMBALAGEM', 'VARCHAR(10)')]
    property Embalagem: string read FEmbalagem write FEmbalagem;
    [TCampo('VE_VALORB', 'NUMERIC(9,4)')]
    property Valorb: double read FValorb write FValorb;
    [TCampo('VE_DESCONTO', 'FLOAT')]
    property Desconto: double read FDesconto write FDesconto;
    [TCampo('VE_VALORC', 'NUMERIC(9,4)')]
    property Valorc: double read FValorc write FValorc;
    [TCampo('VE_OBS', 'VARCHAR(100)')]
    property Obs: string read FObs write FObs;
    [TCampo('VE_GRA', 'INTEGER')]
    property Gra: integer read FGra write FGra;
    [TCampo('VE_SEMENTE_TRATADA', 'CHAR(1)')]
    property Semente_tratada: string read FSemente_tratada write FSemente_tratada;
    [TCampo('VE_VALOR_PARTIDA', 'NUMERIC(12,4)')]
    property Valor_partida: double read FValor_partida write FValor_partida;
    [TCampo('VE_VARIACAO', 'NUMERIC(12,4)')]
    property Variacao: double read FVariacao write FVariacao;
    [TCampo('VE_USU', 'INTEGER')]
    property Usu: integer read FUsu write FUsu;
    property Complementos: TArray<TVeAdicionais> read FComplementos write FComplementos;
    property OpcoesNivel: TArray<TVeOpcoes> read FOpcoesNivel write FOpcoesNivel;    
    function Clone: TVenEst;
  end;

implementation

uses
  FireDAC.Comp.Client;

function TVenEst.Clone: TVenEst;
begin
  Result := TVenEst.Create(TDatabase.Connection);

  Result.Codigo          := Self.Codigo;
  Result.Valor           := Self.Valor;
  Result.Quantidade      := Self.Quantidade;
  Result.Ven             := Self.Ven;
  Result.Pro             := Self.Pro;
  Result.Lucro           := Self.Lucro;
  Result.Valorr          := Self.Valorr;
  Result.Valorl          := Self.Valorl;
  Result.Valorf          := Self.Valorf;
  Result.Diferenca       := Self.Diferenca;
  Result.Liquido         := Self.Liquido;
  Result.Valor2          := Self.Valor2;
  Result.Valorcm         := Self.Valorcm;
  Result.Aliquota        := Self.Aliquota;
  Result.Gtin            := Self.Gtin;
  Result.Embalagem       := Self.Embalagem;
  Result.Valorb          := Self.Valorb;
  Result.Desconto        := Self.Desconto;
  Result.Valorc          := Self.Valorc;
  Result.Obs             := Self.Obs;
  Result.Gra             := Self.Gra;
  Result.Semente_tratada := Self.Semente_tratada;
  Result.Valor_partida   := Self.Valor_partida;
  Result.Variacao        := Self.Variacao;
  Result.Usu             := Self.Usu;
end;

end.
