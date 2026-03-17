unit UnitVeOpcoes.Model;

interface

uses
	{$IFDEF PORTALORM}
	UnitPortalORM.Model,
	UnitDatabase;
	{$ELSE}
	UnitBancoDeDados.Model;
{$ENDIF}

type

	[TRecursoServidor('/veOpcoes')]
	[TNomeTabela('VE_OPCOES', 'VO_CODIGO')]
	TVeOpcoes = class(TTabela)
	private
		{ private declarations }
		FCodigo        : integer;
		FVe            : integer;
		FCodNivel      : integer;
		FQuantidade    : double;
		FValorAdicional: Currency;
	public
		{ public declarations }
		[TCampo('VO_CODIGO', 'INTEGER NOT NULL PRIMARY KEY')]
		property Codigo: integer read FCodigo write FCodigo;
		[TCampo('VO_VE', 'INTEGER')]
		property Ve: integer read FVe write FVe;
		[TCampo('VO_NIVEL', 'INTEGER')]
		property CodNivel: integer read FCodNivel write FCodNivel;
		[TCampo('VO_QUANTIDADE', 'NUMERIC(9,2)')]
		property Quantidade: double read FQuantidade write FQuantidade;
		[TCampo('VO_VALOR', 'NUMERIC(9,2)')]
		property ValorAdicional: Currency read FValorAdicional write FValorAdicional;
		function Clonar: TVeOpcoes;
	end;

implementation

{ TVeOpcoes }

function TVeOpcoes.Clonar: TVeOpcoes;
begin
	Result := TVeOpcoes.Create(TDatabase.Connection);
	Result.CriaTabela;
	Result.Codigo         := Self.Codigo;
	Result.Ve             := Self.Ve;
	Result.CodNivel       := Self.CodNivel;
	Result.Quantidade     := Self.Quantidade;
	Result.ValorAdicional := Self.ValorAdicional;
end;

end.
