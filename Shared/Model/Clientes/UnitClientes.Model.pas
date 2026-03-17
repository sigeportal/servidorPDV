unit UnitClientes.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/clientes')]
  [TNomeTabela('CLIENTES', 'CLI_CODIGO')]
  TClientes = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FNome: string;
    FEndereco: string;
    FBairro: string;
    FCidade: string;
    FCep: string;
    FUf: string;
    FFone: string;
    FEmail: string;
    FDatac: TDateTime;
    FDatau: TDateTime;
    FTipo: string;
    FCelular: string;
    FEndcorresp: string;
    FObs: string;
    FCnpj_cpf: string;
    FSituacao: string;
    FPlano: integer;
    FLimite: double;
    FDatanasc: TDate;
    FRg: string;
    FPai: string;
    FMae: string;
    FFidelidade: string;
    FDesconto: double;
    FConjuge: string;
    FInadimplencia: integer;
    FInsc_estadual: string;
    FInsc_municipal: string;
    FCod_pais: integer;
    FSuframa: string;
    FNumero: string;
    FComplemento: string;
    FClassificacao: double;
    FNota: string;
    FClassificacao2: double;
    FDescontar: string;
    FCadastro: string;
    FData_u_a: TDate;
    FBairroc: string;
    FCidadec: string;
    FLimite_tit: double;
    FTipo_entr: integer;
    FAbc: string;
    FOrdena_abc: integer;
    FVencimento: TDate;
    FCid: integer;
    FRazao_social: string;
    FIndic_ie: string;
    FPmr: integer;
  public
    { public declarations }
    [TCampo('CLI_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('CLI_NOME', 'VARCHAR(50)')]
    property Nome: string read FNome write FNome;
    [TCampo('CLI_ENDERECO', 'VARCHAR(50)')]
    property Endereco: string read FEndereco write FEndereco;
    [TCampo('CLI_BAIRRO', 'VARCHAR(30)')]
    property Bairro: string read FBairro write FBairro;
    [TCampo('CLI_CIDADE', 'VARCHAR(40)')]
    property Cidade: string read FCidade write FCidade;
    [TCampo('CLI_CEP', 'VARCHAR(9)')]
    property Cep: string read FCep write FCep;
    [TCampo('CLI_UF', 'VARCHAR(2)')]
    property Uf: string read FUf write FUf;
    [TCampo('CLI_FONE', 'VARCHAR(14)')]
    property Fone: string read FFone write FFone;
    [TCampo('CLI_EMAIL', 'VARCHAR(100)')]
    property Email: string read FEmail write FEmail;
    [TCampo('CLI_DATAC', 'TIMESTAMP')]
    property Datac: TDateTime read FDatac write FDatac;
    [TCampo('CLI_DATAU', 'TIMESTAMP')]
    property Datau: TDateTime read FDatau write FDatau;
    [TCampo('CLI_TIPO', 'VARCHAR(9)')]
    property Tipo: string read FTipo write FTipo;
    [TCampo('CLI_CELULAR', 'VARCHAR(14)')]
    property Celular: string read FCelular write FCelular;
    [TCampo('CLI_ENDCORRESP', 'VARCHAR(50)')]
    property Endcorresp: string read FEndcorresp write FEndcorresp;
    [TCampo('CLI_OBS', 'VARCHAR(250)')]
    property Obs: string read FObs write FObs;
    [TCampo('CLI_CNPJ_CPF', 'VARCHAR(18)')]
    property Cnpj_cpf: string read FCnpj_cpf write FCnpj_cpf;
    [TCampo('CLI_SITUACAO', 'VARCHAR(15)')]
    property Situacao: string read FSituacao write FSituacao;
    [TCampo('CLI_PLANO', 'SMALLINT')]
    property Plano: integer read FPlano write FPlano;
    [TCampo('CLI_LIMITE', 'NUMERIC(9,2)')]
    property Limite: double read FLimite write FLimite;
    [TCampo('CLI_DATANASC', 'DATE')]
    property Datanasc: TDate read FDatanasc write FDatanasc;
    [TCampo('CLI_RG', 'VARCHAR(18)')]
    property Rg: string read FRg write FRg;
    [TCampo('CLI_PAI', 'VARCHAR(50)')]
    property Pai: string read FPai write FPai;
    [TCampo('CLI_MAE', 'VARCHAR(50)')]
    property Mae: string read FMae write FMae;
    [TCampo('CLI_FIDELIDADE', 'VARCHAR(15)')]
    property Fidelidade: string read FFidelidade write FFidelidade;
    [TCampo('CLI_DESCONTO', 'NUMERIC(3,2)')]
    property Desconto: double read FDesconto write FDesconto;
    [TCampo('CLI_CONJUGE', 'VARCHAR(50)')]
    property Conjuge: string read FConjuge write FConjuge;
    [TCampo('CLI_INADIMPLENCIA', 'SMALLINT')]
    property Inadimplencia: integer read FInadimplencia write FInadimplencia;
    [TCampo('CLI_INSC_ESTADUAL', 'VARCHAR(20)')]
    property Insc_estadual: string read FInsc_estadual write FInsc_estadual;
    [TCampo('CLI_INSC_MUNICIPAL', 'VARCHAR(20)')]
    property Insc_municipal: string read FInsc_municipal write FInsc_municipal;
    [TCampo('CLI_COD_PAIS', 'INTEGER')]
    property Cod_pais: integer read FCod_pais write FCod_pais;
    [TCampo('CLI_SUFRAMA', 'VARCHAR(9)')]
    property Suframa: string read FSuframa write FSuframa;
    [TCampo('CLI_NUMERO', 'VARCHAR(10)')]
    property Numero: string read FNumero write FNumero;
    [TCampo('CLI_COMPLEMENTO', 'VARCHAR(50)')]
    property Complemento: string read FComplemento write FComplemento;
    [TCampo('CLI_CLASSIFICACAO', 'FLOAT')]
    property Classificacao: double read FClassificacao write FClassificacao;
    [TCampo('CLI_NOTA', 'VARCHAR(6)')]
    property Nota: string read FNota write FNota;
    [TCampo('CLI_CLASSIFICACAO2', 'FLOAT')]
    property Classificacao2: double read FClassificacao2 write FClassificacao2;
    [TCampo('CLI_DESCONTAR', 'VARCHAR(4)')]
    property Descontar: string read FDescontar write FDescontar;
    [TCampo('CLI_CADASTRO', 'VARCHAR(15)')]
    property Cadastro: string read FCadastro write FCadastro;
    [TCampo('CLI_DATA_U_A', 'DATE')]
    property Data_u_a: TDate read FData_u_a write FData_u_a;
    [TCampo('CLI_BAIRROC', 'VARCHAR(30)')]
    property Bairroc: string read FBairroc write FBairroc;
    [TCampo('CLI_CIDADEC', 'VARCHAR(40)')]
    property Cidadec: string read FCidadec write FCidadec;
    [TCampo('CLI_LIMITE_TIT', 'NUMERIC(9,2)')]
    property Limite_tit: double read FLimite_tit write FLimite_tit;
    [TCampo('CLI_TIPO_ENTR', 'SMALLINT')]
    property Tipo_entr: integer read FTipo_entr write FTipo_entr;
    [TCampo('CLI_ABC', 'VARCHAR(1)')]
    property Abc: string read FAbc write FAbc;
    [TCampo('CLI_ORDENA_ABC', 'SMALLINT')]
    property Ordena_abc: integer read FOrdena_abc write FOrdena_abc;
    [TCampo('CLI_VENCIMENTO', 'DATE')]
    property Vencimento: TDate read FVencimento write FVencimento;
    [TCampo('CLI_CID', 'INTEGER')]
    property Cid: integer read FCid write FCid;
    [TCampo('CLI_RAZAO_SOCIAL', 'VARCHAR(100)')]
    property Razao_social: string read FRazao_social write FRazao_social;
    [TCampo('CLI_INDIC_IE', 'CHAR(1)')]
    property Indic_ie: string read FIndic_ie write FIndic_ie;
    [TCampo('CLI_PMR', 'INTEGER')]
    property Pmr: integer read FPmr write FPmr;
  end;

implementation

end.
