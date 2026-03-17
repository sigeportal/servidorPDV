unit UnitProdutos.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model, UnitTotalizador.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/produtos')]
  [TNomeTabela('PRODUTOS', 'PRO_CODIGO')]
  TProdutos = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FEst: integer;
    FFor: integer;
    FFabricante: string;
    FQuantidadem: integer;
    FQuantidade: double;
    FValorv: double;
    FValorcm: double;
    FValorc: double;
    FValorl: double;
    FValorf: double;
    FQuantidadef: double;
    FLocal: string;
    FEmbalagem: string;
    FDatauc: TDate;
    FGru: integer;
    FDescricao: string;
    FDataua: TDate;
    FAbc: string;
    FCodbarra: string;
    FValors: double;
    FCodTotalizador: integer;
    FNome: string;
    FEstado: string;
    FGtin: string;
    FIat: string;
    FIppt: string;
    FSit_trib: string;
    FAliqicms_opint: integer;
    FPerc_red_opint: double;
    FUm: integer;
    FCst: string;
    FGenero: integer;
    FTt: integer;
    FNcm: string;
    FCfop: string;
    FEstoque: string;
    FCaminho: string;
    FTipo: string;
    FCest: string;
    FFcp: string;
    FExcecao_ncm: integer;
    FTipo_item: string;
    FBalanca: string;
    FDias_validade: integer;
    FValorv_prazo: double;
    FValidade: string;
    FTexto_semente_tratada: string;
    FCaminho_imagem: string;
    FComo_eh_vendido: string;
    FTotalizador: TTotalizador;
  public
    { public declarations }
    [TCampo('PRO_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('PRO_EST', 'INTEGER')]
    property Est: integer read FEst write FEst;
    [TCampo('PRO_FOR', 'SMALLINT')]
    property CodFor: integer read FFor write FFor;
    [TCampo('PRO_FABRICANTE', 'VARCHAR(20)')]
    property Fabricante: string read FFabricante write FFabricante;
    [TCampo('PRO_QUANTIDADEM', 'SMALLINT')]
    property Quantidadem: integer read FQuantidadem write FQuantidadem;
    [TCampo('PRO_QUANTIDADE', 'NUMERIC(9,2)')]
    property Quantidade: double read FQuantidade write FQuantidade;
    [TCampo('PRO_VALORV', 'NUMERIC(9,4)')]
    property Valorv: double read FValorv write FValorv;
    [TCampo('PRO_VALORCM', 'NUMERIC(9,4)')]
    property Valorcm: double read FValorcm write FValorcm;
    [TCampo('PRO_VALORC', 'NUMERIC(9,4)')]
    property Valorc: double read FValorc write FValorc;
    [TCampo('PRO_VALORL', 'NUMERIC(9,4)')]
    property Valorl: double read FValorl write FValorl;
    [TCampo('PRO_VALORF', 'NUMERIC(9,4)')]
    property Valorf: double read FValorf write FValorf;
    [TCampo('PRO_QUANTIDADEF', 'NUMERIC(9,2)')]
    property Quantidadef: double read FQuantidadef write FQuantidadef;
    [TCampo('PRO_LOCAL', 'VARCHAR(20)')]
    property Local: string read FLocal write FLocal;
    [TCampo('PRO_EMBALAGEM', 'VARCHAR(10)')]
    property Embalagem: string read FEmbalagem write FEmbalagem;
    [TCampo('PRO_DATAUC', 'DATE')]
    property Datauc: TDate read FDatauc write FDatauc;
    [TCampo('PRO_GRU', 'SMALLINT')]
    property Gru: integer read FGru write FGru;
    [TCampo('PRO_DESCRICAO', 'VARCHAR(30)')]
    property Descricao: string read FDescricao write FDescricao;
    [TCampo('PRO_DATAUA', 'DATE')]
    property Dataua: TDate read FDataua write FDataua;
    [TCampo('PRO_ABC', 'VARCHAR(2)')]
    property Abc: string read FAbc write FAbc;
    [TCampo('PRO_CODBARRA', 'VARCHAR(30)')]
    property Codbarra: string read FCodbarra write FCodbarra;
    [TCampo('PRO_VALORS', 'NUMERIC(9,2)')]
    property Valors: double read FValors write FValors;
    [TCampo('PRO_TOTALIZADOR', 'SMALLINT')]
    property CodTotalizador: integer read FCodTotalizador write FCodTotalizador;
    [TCampo('PRO_NOME', 'VARCHAR(50)')]
    property Nome: string read FNome write FNome;
    [TCampo('PRO_ESTADO', 'VARCHAR(8)')]
    property Estado: string read FEstado write FEstado;
    [TCampo('PRO_GTIN', 'VARCHAR(14)')]
    property Gtin: string read FGtin write FGtin;
    [TCampo('PRO_IAT', 'VARCHAR(1)')]
    property Iat: string read FIat write FIat;
    [TCampo('PRO_IPPT', 'VARCHAR(1)')]
    property Ippt: string read FIppt write FIppt;
    [TCampo('PRO_SIT_TRIB', 'VARCHAR(20)')]
    property Sit_trib: string read FSit_trib write FSit_trib;
    [TCampo('PRO_ALIQICMS_OPINT', 'SMALLINT')]
    property Aliqicms_opint: integer read FAliqicms_opint write FAliqicms_opint;
    [TCampo('PRO_PERC_RED_OPINT', 'NUMERIC(9,4)')]
    property Perc_red_opint: double read FPerc_red_opint write FPerc_red_opint;
    [TCampo('PRO_UM', 'SMALLINT')]
    property Um: integer read FUm write FUm;
    [TCampo('PRO_CST', 'VARCHAR(3)')]
    property Cst: string read FCst write FCst;
    [TCampo('PRO_GENERO', 'INTEGER')]
    property Genero: integer read FGenero write FGenero;
    [TCampo('PRO_TT', 'INTEGER')]
    property Tt: integer read FTt write FTt;
    [TCampo('PRO_NCM', 'VARCHAR(10)')]
    property Ncm: string read FNcm write FNcm;
    [TCampo('PRO_CFOP', 'VARCHAR(5)')]
    property Cfop: string read FCfop write FCfop;
    [TCampo('PRO_ESTOQUE', 'VARCHAR(5)')]
    property Estoque: string read FEstoque write FEstoque;
    [TCampo('PRO_CAMINHO', 'VARCHAR(10)')]
    property Caminho: string read FCaminho write FCaminho;
    [TCampo('PRO_TIPO', 'VARCHAR(10)')]
    property Tipo: string read FTipo write FTipo;
    [TCampo('PRO_CEST', 'VARCHAR(10)')]
    property Cest: string read FCest write FCest;
    [TCampo('PRO_FCP', 'CHAR(1)')]
    property Fcp: string read FFcp write FFcp;
    [TCampo('PRO_EXCECAO_NCM', 'SMALLINT')]
    property Excecao_ncm: integer read FExcecao_ncm write FExcecao_ncm;
    [TCampo('PRO_TIPO_ITEM', 'VARCHAR(2)')]
    property Tipo_item: string read FTipo_item write FTipo_item;
    [TCampo('PRO_BALANCA', 'CHAR(1)')]
    property Balanca: string read FBalanca write FBalanca;
    [TCampo('PRO_DIAS_VALIDADE', 'SMALLINT')]
    property Dias_validade: integer read FDias_validade write FDias_validade;
    [TCampo('PRO_VALORV_PRAZO', 'NUMERIC(12,4)')]
    property Valorv_prazo: double read FValorv_prazo write FValorv_prazo;
    [TCampo('PRO_VALIDADE', 'CHAR(1)')]
    property Validade: string read FValidade write FValidade;
    [TCampo('PRO_TEXTO_SEMENTE_TRATADA', 'VARCHAR(200)')]
    property Texto_semente_tratada: string read FTexto_semente_tratada write FTexto_semente_tratada;
    [TCampo('PRO_CAMINHO_IMAGEM', 'VARCHAR(1000)')]
    property Caminho_imagem: string read FCaminho_imagem write FCaminho_imagem;
    [TCampo('PRO_COMO_EH_VENDIDO', 'VARCHAR(10)')]
    property Como_eh_vendido: string read FComo_eh_vendido write FComo_eh_vendido;
    [TRelacionamento('TOTALIZADORES', 'TOT_CODIGO', 'PRO_TOTALIZADOR', TTotalizador, TTipoRelacionamento.UmPraUm)]
    property Totalizador: TTotalizador read FTotalizador write FTotalizador;
  end;

implementation

end.
