unit UnitTamanhos.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model;
  {$ELSE}
  UnitBancoDeDados.Model;
  {$ENDIF}

type
  [TRecursoServidor('/tamanhos')]
  [TNomeTabela('TAMANHOS', 'TAM_CODIGO')]
  TTamanhos = class(TTabela)
  private
    { private declarations }
    FCodigo: integer;
    FDescricao: string;
    FSigla: string;
  public
    { public declarations }
    [TCampo('TAM_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
    property Codigo: integer read FCodigo write FCodigo;
    [TCampo('TAM_DESCRICAO', 'VARCHAR(20)')]
    property Descricao: string read FDescricao write FDescricao;
    [TCampo('TAM_SIGLA', 'CHAR(1)')]
    property Sigla: string read FSigla write FSigla;
  end;

implementation

end.
