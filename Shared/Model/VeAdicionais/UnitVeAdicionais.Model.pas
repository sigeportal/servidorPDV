unit UnitVeAdicionais.Model;

interface

uses
	{$IFDEF PORTALORM}
	UnitPortalORM.Model,
	UnitDatabase;
	{$ELSE}
	UnitBancoDeDados.Model;
{$ENDIF}

type

	[TRecursoServidor('/veAdicionais')]
	[TNomeTabela('VE_ADICIONAIS', 'VA_CODIGO')]
	TVeAdicionais = class(TTabela)
	private
		{ private declarations }
		FCodigo    : integer;
		FVe        : integer;
		FAdi       : integer;
		FQuantidade: double;
    FValor: Currency;
	public
		{ public declarations }
		[TCampo('VA_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
		property Codigo: integer read FCodigo write FCodigo;
		[TCampo('VA_VE', 'INTEGER')]
		property Ve: integer read FVe write FVe;
		[TCampo('VA_ADI', 'INTEGER')]
		property Adi: integer read FAdi write FAdi;
		[TCampo('VA_QUANTIDADE', 'NUMERIC(9,2)')]
		property Quantidade: double read FQuantidade write FQuantidade;
    [TCampo('VA_VALOR', 'NUMERIC(9,2)')]
    property Valor: Currency read FValor write FValor;
		function Clonar: TVeAdicionais;
	end;

implementation

{ TVeAdicionais }

function TVeAdicionais.Clonar: TVeAdicionais;
begin
	Result            := TVeAdicionais.Create(TDatabase.Connection);
  Result.CriaTabela;
	Result.Codigo     := Self.Codigo;
	Result.Ve         := Self.Ve;
	Result.Adi        := Self.Adi;
	Result.Quantidade := Self.Quantidade;
  Result.Valor      := Self.Valor; 
end;

end.
